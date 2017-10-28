import 'dart:async';
import 'package:azuchath_flutter/logic/io/apiclient.dart';
import 'package:azuchath_flutter/logic/azuchath.dart';
import 'package:azuchath_flutter/logic/data/auth.dart';
import 'package:azuchath_flutter/main.dart';
import 'package:azuchath_flutter/ui/ui_utils.dart';
import 'package:flutter/material.dart';

import 'package:url_launcher/url_launcher.dart';

enum _AuthAction {
	LOGIN, SWITCH_FROM_LOGIN_TO_REGISTER, REGISTER, SWITCH_FROM_REGISTER_TO_LOGIN
}

class _GivenData {
	String email;
	String password;

	String name;

	String verificationCode;

	_GivenData(this.email, this.password);
	_GivenData.forRegister(this.email, this.password, this.name, this.verificationCode);
}

typedef void _AuthListener(_AuthAction action, _GivenData data);

class Greeter extends StatefulWidget {

	final Azuchath _azu;

	Greeter(this._azu);

  @override
  State<StatefulWidget> createState() => new _GreeterState(_azu);
}

class _GreeterState extends State<Greeter> {

	final Azuchath _azu;

	_GreeterState(this._azu);

	_GivenData currentData;
	bool showLogin = true;

	bool showLoading = false;
	String showError;

	bool _valInput(String input) => input != null && input.trim().isNotEmpty;

	Future finishWithSession(Session session) async {
		_azu.firebase.requestMsgPerms();
		_azu.data.data.session = session;
		await _azu.data.io.writeData();
		if (_azu.firebase.token != null)
			await _azu.api.writeFcmToken(_azu.firebase.token);
		await _azu.syncWithServer();
	}

	void handleLogin() {
		showLoading = true;
		showError = null;

		if (!_valInput(currentData.email) || !_valInput(currentData.password)) {
			showLoading = false;
			showError = "Bitte alle Felder ausfüllen";
			return;
		}

		_azu.api.loginWithPassword(currentData.email, currentData.password)
		.then((res) {
			if (res.success) {
				finishWithSession(res.session);
			} else {
				//TODO Check if this actually is an auth error
				setState(() {
					showLoading = false;
					showError = "Mit der Kombination aus Nutzernamen und Passwort ist keine Anmeldung möglich";
				});
			}
		}
		, onError: (e) {
			setState(() {
				showLoading = false;
				showError = "Beim Anmelden ist ein Fehler aufgetreten. Bitte versuche es später erneut";
			});
		});
	}

	void handleRegistration() {
		showLoading = true;
		showError = null;

		if (!_valInput(currentData.email) || !_valInput(currentData.password) || !_valInput(currentData.name)) {
			showLoading = false;
			showError = "Bitte alle Felder ausfüllen";
			return;
		}

		_azu.api.register(currentData.email, currentData.name, currentData.password, currentData.verificationCode)
		.then((res) {
			if (res.success) {
				finishWithSession(res.session);
			} else {
				showLoading = false;
				if (res.failureReason == RegisterResponse.FAILURE_INVALID_MAIL)
					showError = "Die eingegebene E-Mail Adresse ist ungültig";
				else if (res.failureReason == RegisterResponse.FAILURE_USER_EXISTS)
					showError = "Es existiert bereits ein Nutzer mit dieser E-Mail Adresse";
				else if (res.failureReason == RegisterResponse.FAILURE_INVALID_VERIFICATION)
					showError = "Der Zugangscode ist ungültig";
				else
					showError = "Es ist auf unserem Server ein Fehler aufgetreten. Bitte versuche es später erneut";

				setState(() {});
			}
		}, onError: (e) {
			showLoading = false;
			showError = "Bei der Registrierung ist ein Fehler aufgetreten. Bitte versuche es später erneut";
			setState(() {});
		});
	}

	void authAction(_AuthAction action, _GivenData data) {
		currentData = data;

		switch (action) {
			case _AuthAction.LOGIN:
				handleLogin();
				break;
			case _AuthAction.REGISTER:
				handleRegistration();
				break;
			case _AuthAction.SWITCH_FROM_LOGIN_TO_REGISTER:
				showLogin = false;
				showError = null;
				break;
			case _AuthAction.SWITCH_FROM_REGISTER_TO_LOGIN:
				showLogin = true;
				showError = null;
				break;
		}

		setState(() {});
	}

	@override
	Widget build(BuildContext context) {
		var entries = <Widget>[
			new Container(
				height: 56.0,
				child: new Image.asset(
					"res/images/hus_logo_white.png",
					fit: BoxFit.contain,
				),
			),
			const Divider(),
		];

		if (showLoading) {
			entries.add(new LinearProgressIndicator());
		} else {
			if (showLogin) {
				entries.add(
					new _LoginWidget(
						authAction,
						initUsername: currentData?.email,
						initPassword: currentData?.password
					)
				);
			} else {
				entries.add(
					new _RegisterWidget(
						authAction,
						initUsername: currentData?.email,
						initName: currentData?.name,
						initPassword: currentData?.password,
						initVerification: currentData?.verificationCode,
					)
				);
			}
		}

		if (showError != null) {
			entries.add(
					new Text(showError, style: new TextStyle(color: Colors.deepOrange))
			);
		}

		entries.add(const Divider());
		entries.add(new Text("Mit der HUS App von der SV erhälst du einen auf dich zugeschnittenen Stunden- und Vertretungsplan. " +
				"Dafür müssen wir dich eindeutig zuordnen können, weshalb du dich erst anmelden musst."));
		entries.add(new Container(
			margin: const EdgeInsets.only(top: 8.0),
		  child: new Row(
		  	mainAxisAlignment: MainAxisAlignment.center,
		    children: [new RaisedButton(
		    	onPressed: () => launch(FEEDBACK_FORM_URL),
		    	child: const Text("HILFE")
		    ),]
		  ),
		));

		return new MaterialApp(
			title: "HUS App",
			theme: new ThemeData(
				brightness: Brightness.dark,
			),
			home: new Scaffold(
				body: new Container(
					padding: const EdgeInsets.only(top: kToolbarHeight, left: 16.0, right: 16.0, bottom: 16.0),
					decoration: new BoxDecoration(
						color: Colors.blueGrey.shade700,
					),
					child: new Column(
					  children: [
					  	new Expanded(
					  	  child: new ListView(
					  	  	children: entries
					  	  ),
					  	),
							new Row(
								mainAxisAlignment: MainAxisAlignment.spaceBetween,
								children: [
									 new Flexible(
									  child: new RichText(
									  	text: createLink(
									  		url: PRIVACY_URL,
									  		text: "Datenschutzerklärung",
									  		style: const TextStyle(color: Colors.white70)
									  	)
									  ),
									),
									new Flexible(
										child: new RichText(
											text: createLink(
												url: RESET_PW_URL,
												text: "Passwort vergessen",
												style: const TextStyle(color: Colors.white70)
											)
										)
									)
								]
							),
						],
					),
				),
			),
		);
	}
}

class _LoginWidget extends StatefulWidget {

	final _AuthListener cb;
	final String initUsername;
	final String initPassword;

	_LoginWidget(this.cb, {this.initUsername, this.initPassword});

	@override
	State<StatefulWidget> createState() => new _LoginState(cb, initMail: initUsername, initPassword: initPassword);
}

class _LoginState extends State<_LoginWidget> {

	TextEditingController controlMail;
	TextEditingController controlPassword;

	final String initMail;
	final String initPassword;

	final _AuthListener cb;

	_LoginState(this.cb, {this.initMail, this.initPassword}) {
		controlMail = new TextEditingController(text: initMail);
		controlPassword =  new TextEditingController(text: initPassword);
	}

	_GivenData obtainData() =>
			new _GivenData(controlMail.text, controlPassword.text);

	void onLoginClick() {
		cb(_AuthAction.LOGIN, obtainData());
	}

	void onSwitchRegisterClick() {
		cb(_AuthAction.SWITCH_FROM_LOGIN_TO_REGISTER, obtainData());
	}

	@override
	Widget build(BuildContext context) {
		return new Center(
			child: new Column(
				children: [
					new Text("Anmelden", style: Theme.of(context).textTheme.display2.copyWith(fontWeight: FontWeight.bold)),
					new TextField(
						keyboardType: TextInputType.emailAddress,
						controller: controlMail,
						decoration: new InputDecoration(
							icon: new Icon(Icons.person),
							hintText: "E-Mail"
						),
					),
					new TextField(
						controller: controlPassword,
						obscureText: true,
						decoration: new InputDecoration(
								icon: new Icon(Icons.lock),
								hintText: "Passwort"
						),
					),
					new Row(
						mainAxisAlignment: MainAxisAlignment.spaceBetween,
						children: [
							new RaisedButton(
								color: Colors.lightGreen,
								onPressed: onLoginClick,
								child: new Text("Anmelden")
							),
							new FlatButton(
								color: Colors.grey.shade600,
								onPressed: onSwitchRegisterClick,
								child: new Text("Neuer Account")
							)
						]
					)
				]
			)
		);
	}
}

class _RegisterWidget extends StatefulWidget {

	final _AuthListener cb;
	final String initUsername;
	final String initName;
	final String initPassword;
	final String initVerification;

	_RegisterWidget(this.cb, {this.initUsername, this.initName, this.initPassword, this.initVerification});

	@override
	State<StatefulWidget> createState() =>
		new _RegisterState(cb, initMail: initUsername, initName: initName,
				initPassword: initPassword, initVerification: initVerification);

}

class _RegisterState extends State<_RegisterWidget> {

	TextEditingController controlMail;
	TextEditingController controlName;
	TextEditingController controlPassword;
	TextEditingController controlVerification;

	final String initMail;
	final String initName;
	final String initPassword;
	final String initVerification;

	final _AuthListener cb;

	_RegisterState(this.cb, {this.initMail, this.initName, this.initPassword, this.initVerification}) {
		controlMail = new TextEditingController(text: initMail);
		controlName = new TextEditingController(text: initName);
		controlPassword =  new TextEditingController(text: initPassword);
		controlVerification = new TextEditingController(text: initVerification);
	}

	_GivenData obtainData() =>
			new _GivenData.forRegister(controlMail.text, controlPassword.text, controlName.text, controlVerification.text);

	void onRegisterClick() {
		cb(_AuthAction.REGISTER, obtainData());
	}

	void onSwitchLoginClick() {
		cb(_AuthAction.SWITCH_FROM_REGISTER_TO_LOGIN, obtainData());
	}

	@override
	Widget build(BuildContext context) {
		return new Center(
				child: new Column(
						children: [
							new Text("Registrieren", style: Theme.of(context).textTheme.display2.copyWith(fontWeight: FontWeight.bold)),
							new TextField(
								keyboardType: TextInputType.emailAddress,
								controller: controlMail,
								decoration: new InputDecoration(
										icon: new Icon(Icons.person),
										hintText: "E-Mail"
								),
							),
							new TextField(
								controller: controlName,
								decoration: new InputDecoration(
										icon: new Icon(Icons.verified_user),
										hintText: "Vor- und Nachname"
								),
							),
							new TextField(
								controller: controlPassword,
								obscureText: true,
								decoration: new InputDecoration(
										icon: new Icon(Icons.lock),
										hintText: "Passwort"
								),
							),
							new TextField(
								controller: controlVerification,
								decoration: new InputDecoration(
										icon: new Icon(Icons.vpn_lock),
										hintText: "Passwort zum DSB als Bestätigung"
								),
							),
							new Row(
									mainAxisAlignment: MainAxisAlignment.spaceBetween,
									children: [
										new RaisedButton(
												color: Colors.lightGreen,
												onPressed: onRegisterClick,
												child: new Text("Registrieren")
										),
										new RaisedButton(
												color: Colors.grey.shade600,
												onPressed: onSwitchLoginClick,
												child: new Text("Lieber Anmelden")
										)
									]
							)
						]
				)
		);
	}
}