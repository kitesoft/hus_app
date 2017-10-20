import 'dart:async';

import 'package:azuchath_flutter/logic/azuchath.dart';
import 'package:azuchath_flutter/ui/login_greeter.dart';
import 'package:azuchath_flutter/ui/ui_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

const String FEEDBACK_FORM_URL = "https://docs.google.com/forms/d/e/1FAIpQLSen2rs-uOwnPoepPOtkpp5yH3mQEdz_g_UBFoV0dOJkdH-OLQ/viewform?usp=sf_link";
const String GITHUB_URL = "https://github.com/simolus3/hus_app";
const String PRIVACY_URL = "https://husbot.tutorialfactory.org/legal/privacy.html";
const String RESET_PW_URL = "https://husnews.tutorialfactory.org/newsystem/login/recoverpw.php";

void main() {
	var azu = new Azuchath();

	/*
	We need this onFrame callback to scroll to the end of listviews, as there is
	not apparent way to achieve this provided by the framework. This uses a
	horrible hack further explained in ui/pages/chat_content.dart.
	We don't need to close the controller as it will be active during the entire
	app session.
	 */
	// ignore: close_sinks
	var frameController = new StreamController<Duration>.broadcast();
	azu.onNewFrame = frameController.stream;

	runApp(new AzuchathApp(azu));

	SchedulerBinding.instance.addPersistentFrameCallback((d) {
		frameController.add(d);
	});
}

class AzuchathApp extends StatefulWidget {

	final Azuchath azu;

	AzuchathApp(this.azu);

  @override
  State<StatefulWidget> createState() => new AppState(azu);
}

class AppState extends State<AzuchathApp> with WidgetsBindingObserver {

	Azuchath azu;

	AppState(this.azu) {
		azu.start().then((_) => onDataLoaded(null));
		azu.onDataLoaded.listen(onDataLoaded);
	}

	@override
	void initState() {
		super.initState();
		WidgetsBinding.instance.addObserver(this);
	}

	@override
	void dispose() {
		WidgetsBinding.instance.removeObserver(this);
		super.dispose();
	}

	@override
	void didChangeAppLifecycleState(AppLifecycleState state) {
		if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
			azu.onAppInBackground();
		} else if (state == AppLifecycleState.resumed) {
			azu.onAppInForeground();
		}
	}

  @override
  Widget build(BuildContext context) {
		if (!azu.ready) {
			return new LaunchScreen();
		}

		if (!azu.data.isLoggedIn) {
			return new Greeter(azu);
		}

		return new MaterialApp(
			title: 'HUS App',
			supportedLocales: const [const Locale("de", "DE")],
			theme: new ThemeData(
				primaryColor: Colors.deepOrangeAccent,
				accentColor: Colors.indigo
			),
			home: new HUSScaffold(azu),
		);
  }

  void onDataLoaded(DataLoadedEvent event) {
    setState(() => {});
  } //rebuild children
}

class LaunchScreen extends StatelessWidget {

  @override
  Widget build(BuildContext context) {
    return new Container(
			color: Colors.orangeAccent,
			child: new Center(
				child: new Column(
					mainAxisAlignment: MainAxisAlignment.center,
					children: [
						new Expanded(flex: 30, child: new Container()),
						new Expanded(
							flex: 15,
							child: new Image.asset(
								"res/images/hus_logo_white.png",
								fit: BoxFit.fill,
							),
						),
						new Expanded(flex: 5, child: new Container()),
						new Text(
							"HUS", textDirection: TextDirection.ltr,
							style: Theme.of(context).textTheme.display3.copyWith(color: Colors.white, fontWeight: FontWeight.bold)
						),
						new Expanded(flex: 65, child: new Container()),
					]
				)
			)
		);
  }
}