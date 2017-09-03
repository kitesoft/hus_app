import 'dart:async';
import 'package:azuchath_flutter/logic/azuchath.dart';
import 'package:azuchath_flutter/logic/data/usercontent.dart';
import 'package:azuchath_flutter/ui/editor/manage_content.dart';
import 'package:azuchath_flutter/ui/homework_overview.dart';
import 'package:azuchath_flutter/ui/login_greeter.dart';
import 'package:azuchath_flutter/ui/settings/settings_ui.dart';
import 'package:azuchath_flutter/ui/timeline_lesson.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

const String FEEDBACK_FORM_URL = "https://docs.google.com/forms/d/e/1FAIpQLSen2rs-uOwnPoepPOtkpp5yH3mQEdz_g_UBFoV0dOJkdH-OLQ/viewform?usp=sf_link";
const String GITHUB_URL = "https://github.com/simolus3/hus_app";
const String PRIVACY_URL = "https://husbot.tutorialfactory.org/legal/privacy.html";
const String RESET_PW_URL = "https://husnews.tutorialfactory.org/newsystem/login/recoverpw.php";

void main() {
	var azu = new Azuchath();
	runApp(new AzuchathApp(azu));
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
			theme: new ThemeData(
					primaryColor: Colors.deepOrangeAccent,
					accentColor: Colors.indigo
			),
			home: new HomeScreen(azu),
		);
  }

  void onDataLoaded(DataLoadedEvent event) {
    setState(() => {});
  } //rebuild children
}

class HomeScreen extends StatefulWidget {

	final Azuchath azu;

	HomeScreen(this.azu);

  @override
  State<StatefulWidget> createState() {
    return new HomeScreenState(azu);
  }
}

class HomeScreenState extends State<HomeScreen> {

	GlobalKey<RefreshIndicatorState> _refreshIndicatorKey = new GlobalKey<
			RefreshIndicatorState>();
	GlobalKey<ScaffoldState> _scaffoldState = new GlobalKey<ScaffoldState>();
	GlobalKey<LessonsState> _timelineState = new GlobalKey<LessonsState>();

	Azuchath azu;
	StreamSubscription listener;

	PageController _pageController;
	int _bottomSheetIndex = 0;
	bool reselectedTab = false;

	bool titleEasterEgg = false;

	HomeScreenState(this.azu);

	@override
	void initState() {
		super.initState();

		listener = azu.onDataLoaded.listen(onDataLoaded);
		_pageController = new PageController();
	}

	@override
	void dispose() {
		listener.cancel();
		_pageController.dispose();

		super.dispose();
	}

	void _hwEdit(Homework hw) {
		openAddContent(hw).then((_) => setState(() {}));
	}

	void _hwDelete(Homework hw) {
		if (_timelineState.currentState != null) {
			_timelineState.currentState.setState(() {});
		}
	}

	void onPageChanged(int page) {
		setState(() {
			_bottomSheetIndex = page;
		});
	}

	void onBottomBarTap(int index) {
		setState(() {
			if (_bottomSheetIndex == index)
				reselectedTab = true;
			else
				_bottomSheetIndex = index;

			_pageController.animateToPage(
					index,
					duration: const Duration(milliseconds: 300),
					curve: Curves.ease
			);
		});
	}

	Future openAddContent([dynamic toEdit]) async {
		ContentNavResponse response = await Navigator.of(context).push(
			new MaterialPageRoute<ContentNavResponse>(
				builder: (_) => new AddContent(azu, toEdit)
			)
		);

		if (response != null && response.success)
			await startSync();
	}

	void openSettings() {
		Navigator.of(context).push(
				new MaterialPageRoute<ContentNavResponse>(
						builder: (_) => new SettingsScreen(azu)
				)
		);
	}

	Future startSync() {
		var refreshState = _refreshIndicatorKey.currentState;
		return refreshState?.show();
	}

	Future _onRefreshSwipe() async => await azu.syncWithServer();

	void onDataLoaded(DataLoadedEvent e) {
		if (e.success) {
			if (_timelineState.currentState != null && !e.simulated) {
				_timelineState.currentState.markTimelineChanged();
			}

			setState(() => {});
		} else {
			_scaffoldState.currentState?.showSnackBar(
				new SnackBar(
					duration: const Duration(milliseconds: 2500),
					content: const Text("Fehler beim Akualisieren, versuche es später erneut")
				)
			);
		}
	}

	PopupMenuButton buildPopupMenu(BuildContext ctx) {
		return new PopupMenuButton(
			onSelected: (v) => v == 0 ? openSettings() : startSync(),
			itemBuilder: (ctx) => [
				const PopupMenuItem(
					value: 0,
					child: const Text("Einstellungen")
				),
				const PopupMenuItem(
					value: 1,
					child: const Text("Aktualisieren")
				)
			]
		);
	}

	RefreshIndicator _buildRefresherAround(Widget child) => new RefreshIndicator(
				key: _refreshIndicatorKey,
				displacement: 20.0,
				child: child,
				onRefresh: _onRefreshSwipe
		);

  @override
  Widget build(BuildContext context) {
		Widget timeline = new LessonTimeline(azu, startSync, key: _timelineState);
		Widget homework = new HomeworkOverview(azu, _hwEdit, _hwDelete);

		//Place a refresh indicator around the content currently shown (can't place
		//the indicator outside of pageview as it does not scroll)
		if (_bottomSheetIndex == 0) {
			if (reselectedTab) {
				_timelineState.currentState?.scrollToTop();
				reselectedTab = false;
			}
			timeline = _buildRefresherAround(timeline);
		} else if (_bottomSheetIndex == 1) {
			homework = _buildRefresherAround(homework);
		}

		var body = new PageView(
			children: [timeline, homework],
			controller: _pageController,
			onPageChanged: onPageChanged,
		);

		var appBarActions = <Widget>[];
		appBarActions.add(buildPopupMenu(context));

		return new Scaffold(
				key: _scaffoldState,
				appBar: new AppBar(
						title: new GestureDetector(
							onLongPress: () {
							  HapticFeedback.vibrate();
							  setState(() {
							    titleEasterEgg = !titleEasterEgg;
									_timelineState.currentState?.noLessonsEasterEgg = titleEasterEgg;
							  });
							},
							child: titleEasterEgg ?
								const Text('HUS++', style: const TextStyle(color: Colors.yellow, fontWeight: FontWeight.bold)) :
								const Text('HUS')
						),
						actions: appBarActions
				),
				body: body,
				floatingActionButton: new FloatingActionButton(
						child: titleEasterEgg ? const Icon(Icons.sentiment_satisfied) :
							const Icon(Icons.add),
						onPressed: openAddContent),
				bottomNavigationBar: new BottomNavigationBar(
						onTap: onBottomBarTap,
						currentIndex: _bottomSheetIndex,
						items: [
							const BottomNavigationBarItem(
									icon: const Icon(Icons.home),
									title: const Text("Unterricht"),
									backgroundColor: Colors.red),
							const BottomNavigationBarItem(
									icon: const Icon(Icons.assignment),
									title: const Text("Zu erledigen"),
									backgroundColor: Colors.green),
						],
						type: BottomNavigationBarType.shifting
				),
		);
  }
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
							"HUS",
							style: Theme.of(context).textTheme.display3.copyWith(color: Colors.white, fontWeight: FontWeight.bold)
						),
						new Expanded(flex: 65, child: new Container()),
					]
				)
			)
		);
  }
}