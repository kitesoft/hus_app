import 'dart:async';
import 'package:azuchath_flutter/logic/azuchath.dart';
import 'package:azuchath_flutter/logic/data/auth.dart';
import 'package:azuchath_flutter/logic/data/manager.dart';
import 'package:azuchath_flutter/logic/preferences.dart';
import 'package:azuchath_flutter/main.dart';
import 'package:azuchath_flutter/ui/settings/course_selection.dart';
import 'package:azuchath_flutter/ui/ui_core.dart';
import 'package:azuchath_flutter/ui/ui_utils.dart';
import 'package:flutter/material.dart';

import 'package:url_launcher/url_launcher.dart';

import 'package:package_info/package_info.dart' as package_info;

class SettingsScreen extends StatefulWidget {
  final Azuchath _azu;

  SettingsScreen(this._azu);

  @override
  State<StatefulWidget> createState() => new _SettingsState();
}

class _SettingsState extends State<SettingsScreen> {

	Azuchath get _azu => widget._azu;

  String appVersion = "??";

  @override
	void initState() {
  	super.initState();

		var loadState = () async {
			String versionName = await package_info.version;
			String versionCode = await package_info.buildNumber;

			setState(() {
				appVersion = "$versionName ($versionCode)";
			});
		};

		loadState();
	}


  Future logOut(BuildContext ctx) async {
    await _azu.api.logout();

		_azu.data.data = new DataStorage.empty();
		_azu.messages.deleteLocalData();
		await _azu.data.io.writeData();

		Navigator.pop(ctx);

		if (_azu.timeline != null)
			_azu.timeline.entries.clear();
		_azu.fireDataLoaded(new DataLoadedEvent()..success = true);
  }

  void setSubscription(BuildContext ctx) {
    Navigator.of(ctx).push(new MaterialPageRoute(
        builder: (_) => new CourseSelector(
            _azu, _azu.data.data.session.user.subscription)));
  }

  void onPreferencesChanged() {
  	
	}

	Widget _buildInfoRow() {
		final ThemeData themeData = Theme.of(context);
		final TextStyle aboutTextStyle = themeData.textTheme.body2;
		final TextStyle linkStyle = themeData.textTheme.body2.copyWith(color: themeData.accentColor);

		return new Row(
			mainAxisAlignment: MainAxisAlignment.spaceBetween,
			children: [
				new FlatButton(
					child: const Text("ÜBER DIE APP", style: const TextStyle(color: Colors.red)),
					onPressed: () => showAboutDialog(
						context: context,
						applicationVersion: appVersion,
						applicationName: "HUS App",
						applicationIcon:
						new Container(
							color: Colors.blue,
							child: new Image.asset(
								"res/images/hus_logo_white.png",
								width: 50.0,
								height: 50.0,
							),
						),
						applicationLegalese: '© Simon Binder',
						children: <Widget>[
							new Padding(
								padding: const EdgeInsets.only(top: 24.0),
								child: new RichText(
									text: new TextSpan(
										children: <TextSpan>[
											new TextSpan(
												style: aboutTextStyle,
												text:
												"Alle verwendeten Daten sind öffentlich oder in unserer "
											),
											createLink(
												style: linkStyle,
												url: PRIVACY_URL,
												text: "Datenschutzerklärung"
											),
											new TextSpan(
												style: aboutTextStyle,
												text:
												" vermerkt. Wir können keine Garantie dafür geben, "
												"dass die angegebenen Daten korrekt bzw. vollständig "
												"sind.\n"
												"Der Quelltext dieser App ist auf "
											),
											createLink(
												style: linkStyle,
												url: GITHUB_URL,
												text: 'Github'
											),
											new TextSpan(
												style: aboutTextStyle,
												text:
												" abrufbar.\n\n"
												"Wir danken den Entwicklern der quelloffenen Software, die von "
												"diesem Projekt verwendet wird. Die Lizenzen dieser sind hier "
												"einsehbar:"
											),
										]
									)
								)
							)
						]
					)
				),
				new FlatButton(
					onPressed: () => launch(FEEDBACK_FORM_URL),
					child: const Text("FEHLER MELDEN", style: const TextStyle(color: Colors.green))
				)
			]
		);
	}

  @override
  Widget build(BuildContext context) {
    if (!_azu.data.isLoggedIn) return null;

		var children = <Widget>[
			new UserInfoWidget(_azu.data.data.session.user,
				() => logOut(context), () => setSubscription(context)),
			const Divider(),
		];

		if (_azu.data.data.session.user.type == AccountType.STUDENT) {
			children.add(
				new FlatButton(
					onPressed: () => setSubscription(context),
					child: const Text(
						"KLASSE UND KURSE FESTLEGEN",
						style: const TextStyle(color: Colors.blue)
					)
				)
			);
			children.add(const Divider());
		}
		children.add(_buildInfoRow());
		children.add(const Divider());
		children.add(new PreferencesWidget(_azu, onPreferencesChanged));

		return new HUSScaffold(_azu,
			title: "Einstellungen",
			content: new SingleChildScrollView(
				child: new Container(
					margin: const EdgeInsets.all(16.0),
					child: new Column(
						crossAxisAlignment: CrossAxisAlignment.start,
						children: children
					)
				)
			)
		);
  }
}

class UserInfoWidget extends StatelessWidget {
  final AuthenticatedUser user;

  final VoidCallback logoutCb;
  final VoidCallback setSubscriptionCb;

  UserInfoWidget(this.user, this.logoutCb, this.setSubscriptionCb);

  String _accTypeDesc() {
  	switch (user.type ?? AccountType.STUDENT) {
			case AccountType.STUDENT:
				return "Schüler";
			case AccountType.TEACHER:
				return "Lehrer";
		}
		return "Accounttyp unbekannt";
	}

  @override
  Widget build(BuildContext context) {
		return new Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      new Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        new Text("Angemeldet als",
					style: smallText(context).copyWith(fontWeight: FontWeight.bold)),
        new FlatButton(
					onPressed: logoutCb,
					child: const Text("ABMELDEN",
						style: const TextStyle(color: Colors.red)))
      ]),
      new Container(
				margin: const EdgeInsets.symmetric(horizontal: 8.0),
				child: new Row(
					mainAxisAlignment: MainAxisAlignment.start,
					children: [
						new Text(user.name, style: mediumText(context)),
						user.verified ?
							new Icon(Icons.verified_user, color: Colors.lightBlue) :
							new Container()
					]
				)
			),
			new Container(
				margin: const EdgeInsets.only(left: 8.0),
				child: new Text(_accTypeDesc(), style: smallText(context)),
			),
    ]);
  }
}

class PreferencesWidget extends StatefulWidget {

	final Azuchath azuchath;
	final VoidCallback onPreferencesChanged;

	PreferencesWidget(this.azuchath, this.onPreferencesChanged);

  @override
  State<StatefulWidget> createState() => new PreferenceState();
}

class PreferenceState extends State<PreferencesWidget> {

	void _onShowTimeIndicatorChanged(bool val) {
		setState(() {
				widget.azuchath.preferences.showNextTimeIndicator = val;
				widget.azuchath.preferences.saveToFile();
		});
	}

	void _onShowFreePeriodChanged(bool val) {
		setState(() {
			widget.azuchath.preferences.showFreePeriod = val;
			widget.azuchath.rebuildTimetable();
			widget.azuchath.preferences.saveToFile();
		});
	}

	void _onLessonTimeModeChanged(LessonTimeMode mode) {
		setState(() {
			widget.azuchath.preferences.timeMode = mode;
			widget.azuchath.preferences.saveToFile();
		});
	}

  @override
  Widget build(BuildContext context) {
		var theme = Theme.of(context).textTheme;

  	return new Column(
			crossAxisAlignment: CrossAxisAlignment.start,
			mainAxisSize: MainAxisSize.min,
			children: [
				new CheckboxListTile(
					title: const Text("Restzeit bis nächste Unterrichtsstunde"),
					subtitle: const Text("Zeigt die Zeit bis zur nächsten Unterrichtsstunde über der Karte an"),
					value: widget.azuchath.preferences.showNextTimeIndicator,
					onChanged: _onShowTimeIndicatorChanged,
					dense: true,
				),
				new CheckboxListTile(
					title: const Text("Freistunden anzeigen"),
					subtitle: const Text("Freistunden werden explizit als Einträge angezeigt"),
					value: widget.azuchath.preferences.showFreePeriod,
					onChanged: _onShowFreePeriodChanged,
					dense: true,
				),

				new Text("Anzeige der Zeit:", style: theme.body1),
				new RadioListTile<LessonTimeMode>(
					title: const Text("Schulstunden"),
					subtitle: const Text("zB. 1. bis 2. Stunde"),
					value: LessonTimeMode.SCHOOL_HOUR,
					groupValue: widget.azuchath.preferences.timeMode,
					onChanged: _onLessonTimeModeChanged,
					dense: true,
				),
				new RadioListTile<LessonTimeMode>(
					title: const Text("genaue Zeit"),
					subtitle: const Text("z.B. 7.55 bis 9:25"),
					value: LessonTimeMode.EXACT_TIME,
					groupValue: widget.azuchath.preferences.timeMode,
					onChanged: _onLessonTimeModeChanged,
					dense: true,
				),
			]
		);
  }
}