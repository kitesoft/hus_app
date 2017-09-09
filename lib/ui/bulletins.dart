import 'package:azuchath_flutter/logic/azuchath.dart';
import 'package:azuchath_flutter/logic/data/timeinfo.dart';
import 'package:azuchath_flutter/logic/io/apiclient.dart';
import 'package:azuchath_flutter/ui/ui_utils.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

enum _LoadingState {

	LOADING, ERROR, LOADED

}

class BulletinScreen extends StatefulWidget {

	final Azuchath azu;

	BulletinScreen(this.azu);

  @override
  State<StatefulWidget> createState() => new BulletinState();
}

class BulletinState extends State<BulletinScreen> {

	_LoadingState state;
	List<Bulletin> bulletins;

	BulletinState() {
		state = _LoadingState.LOADING;
	}

	@override
	void initState() {
		super.initState();
		_loadBulletins();
	}

	void _loadBulletins() {
		widget.azu.api.getBulletins().then((BulletinResponse res) {
			if (res.success) {
				bulletins = res.bulletins;
				state = _LoadingState.LOADED;
			} else {
				state = _LoadingState.ERROR;
			}

			setState(() {});
		}, onError: () {
			setState(() => state = _LoadingState.ERROR);
		});
	}

	Widget generateLoadingScreen(BuildContext context) {
		return new Center(
		  child: new Column(
		  	mainAxisAlignment: MainAxisAlignment.center,
		  	crossAxisAlignment: CrossAxisAlignment.center,
		  	mainAxisSize: MainAxisSize.max,
		  	children: [
		  		new CircularProgressIndicator(),
		  		new Text("Die Aushänge werden geladen", style: mediumText(context)),
					new Text("Bitte gedulde dich noch einen Moment", style: smallText(context))
		  	],
		  ),
		);
	}

	Widget generateErrorScreen(BuildContext context) {
		return new Center(
			child: new Column(
				mainAxisAlignment: MainAxisAlignment.center,
				crossAxisAlignment: CrossAxisAlignment.center,
				mainAxisSize: MainAxisSize.max,
				children: [
					new Text("Ein Fehler ist aufgetreten", style: mediumText(context)),
					new Text("Bitte stelle sicher, dass du eine aktive Internetverbindung besitzt oder versuche es später erneut", style: smallText(context))
				],
			),
		);
	}

	void showDetail(Bulletin b, BuildContext ctx) {
		showDialog(
			context: ctx,
			child: new Dialog(
			  child: new GestureDetector(
					onTap: () {
						Navigator.of(context).pop();
					},
			    child: new Column(
			    	mainAxisSize: MainAxisSize.min,
			    	children: [
			    		new Container(
			    			margin: const EdgeInsets.only(top: 4.0),
								child: new Text(b.title, style: mediumText(ctx))
							),
			    		const Divider(),
			    		new Image.network(b.url, fit: BoxFit.fill),
							const Divider(),
							new IconButton(icon: new Icon(Icons.open_in_browser), onPressed: () {
								launch(b.url);
							})
			    	]
			    ),
			  ),
			)
		);
	}

	Widget generateBulletinList(BuildContext context) {
		var children = <Widget>[
			new Container(
				margin: const EdgeInsets.symmetric(vertical: 12.0, horizontal: 4.0),
				child: new Text(
					"Klicke auf einen Eintrag, um ihn azuzeigen",
					style: mediumText(context).copyWith(color: Colors.black),
				)
			)
		];

		for (var b in bulletins) {
			children.add(
				new GestureDetector(
					onTap: () => showDetail(b, context),
				  child: new Container(
				  	margin: const EdgeInsets.all(4.0),
				    child: new Row(
				    	mainAxisAlignment: MainAxisAlignment.spaceBetween,
				      children: [
				      	new Flexible(
								  child: new Text(
								  	b.title,
								  	style: mediumText(context)
								  ),
								),
								new Container(
									margin: const EdgeInsets.only(right: 4.0),
								  child: new GestureDetector(
								  	child: new Icon(Icons.open_in_browser),
								  	onTap: () {
								  		launch(b.url);
								  	}
								  ),
								)
							]
				    ),
				  ),
				)
			);
			children.add(const Divider());
		}

		return new ListView(
			children: children,
		);
	}

  @override
  Widget build(BuildContext context) {
		var content;
		switch (state) {
			case _LoadingState.LOADING:
				content = generateLoadingScreen(context);
				break;
			case _LoadingState.LOADED:
				content = generateBulletinList(context);
				break;
			case _LoadingState.ERROR:
				content = generateErrorScreen(context);
				break;
		}

    return new Scaffold(
			appBar: new AppBar(
				title: const Text("Aushänge"),
			),
			body: content,
		);
  }
}
