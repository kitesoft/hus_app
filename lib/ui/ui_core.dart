import 'dart:async';
import 'dart:io';

import 'package:azuchath_flutter/logic/azuchath.dart';
import 'package:azuchath_flutter/logic/data/messages.dart';
import 'package:azuchath_flutter/logic/data/usercontent.dart';
import 'package:azuchath_flutter/ui/editor/manage_content.dart';
import 'package:azuchath_flutter/ui/pages/bulletins.dart';
import 'package:azuchath_flutter/ui/pages/chat_content.dart';
import 'package:azuchath_flutter/ui/pages/chat_overview.dart';
import 'package:azuchath_flutter/ui/pages/exams.dart';
import 'package:azuchath_flutter/ui/pages/homework_overview.dart';
import 'package:azuchath_flutter/ui/pages/timeline_lesson.dart';
import 'package:azuchath_flutter/ui/settings/course_selection.dart';
import 'package:azuchath_flutter/ui/settings/settings_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';

const bool _FORCE_IOS = false;

enum _ContentPage {
	LESSONS, HOMEWORK, EXAMS, BULLETINS, MESSAGES
}

class HUSScaffold extends StatefulWidget {

	//TODO iOS Design won't show the CupertinoAppBar for some reason, disabling
	static bool isIos() => /*Platform.isIOS || _FORCE_IOS*/ false;

	final Azuchath azuchath;

	final String title;
	final Widget content;
	final Widget action;

	HUSScaffold(this.azuchath, {this.title, this.content, this.action});

	static _HUSState of(BuildContext context) {
		return context.ancestorStateOfType(const TypeMatcher<_HUSState>());
	}

  @override
  State<StatefulWidget> createState() => new _HUSState();
}

class _HUSState extends State<HUSScaffold> {

	final GlobalKey<ScaffoldState> _scaffoldKey = new GlobalKey();
	final GlobalKey<RefreshIndicatorState> _refreshIndicatorKey = new GlobalKey
		<RefreshIndicatorState>();

	StreamSubscription listener;

	bool get useIos => HUSScaffold.isIos();
	bool get primaryScreen => widget.content == null;
	String get title => widget.title ?? "HUS";
	Azuchath get azuchath => widget.azuchath;

	_ContentPage _currentPage = _ContentPage.LESSONS;

	@override
	void initState() {
		super.initState();

		listener = azuchath.onDataLoaded.listen(_onDataLoaded);
	}

	@override
	void dispose() {
		listener.cancel();

		super.dispose();
	}

	void _onDataLoaded(DataLoadedEvent e) {
		if (e.success) {
			//TODO call markTimelineChanged() in timeline_lesson somehow
			setState(() => {});
		} else {
			_scaffoldKey.currentState?.showSnackBar(
				new SnackBar(
					duration: const Duration(milliseconds: 2500),
					content: const Text("Fehler beim Akualisieren, versuche es später erneut")
				)
			);
		}
	}

	Future showEditHomework(Homework toEdit) async {
		var response = await _showRoute<ContentNavResponse>(
					(_) => new AddContent(azuchath, toEdit));

		if (response != null && response.success)
			await startSync();
	}

	void showCreateHomework() {
		showEditHomework(null);
	}

	void showSettings() {
		_showRoute<Null>((_) => new SettingsScreen(azuchath));
	}

	void showCourseSelection() {
		_showRoute<Null>((_) => new CourseSelector(azuchath));
	}

	void showExamDetails(Exam exam) {
		_showRoute<Null>((_) => new ExamDetailScreen(azuchath, exam));
	}

	void showConversation(Conversation conversation) {
		_showRoute<Null>((_) => new ConversationMessages(azuchath, conversation));
	}

	Future<T> _showRoute<T>(WidgetBuilder builder) {
		if (useIos) {
			return Navigator.of(context).push(
				new CupertinoPageRoute<T>(
					builder: builder
				)
			);
		} else {
			return Navigator.of(context).push(
				new MaterialPageRoute<T>(
					builder: builder,
				)
			);
		}
	}

	Future _onRefreshSwipe() async => await azuchath.syncWithServer();

	Future startSync() {
		var refreshState = _refreshIndicatorKey.currentState;
		return refreshState?.show();
	}

	PopupMenuButton _buildPopupMenu(BuildContext ctx) {
		return new PopupMenuButton(
				onSelected: (v) {
					switch (v) {
						case 0: //Settings
							showSettings();
							break;
						case 1: //Refresh
							startSync();
							break;
					}
				},
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

	VoidCallback _changeContentFunction(_ContentPage target, BuildContext ctx) {
		return () {
			setState(() {
				Navigator.pop(ctx); //will call setState
				this._currentPage = target;
			});
		};
	}

	void _openDrawer() {
		_scaffoldKey.currentState.openDrawer();
	}

	Widget _createAppBar(BuildContext context) {
		final title = new Text(this.title);
		final popup = _buildPopupMenu(context);

		final Widget openDrawer =  useIos ?
			new CupertinoButton(
				child: const Icon(Icons.menu),
				onPressed: _openDrawer
			) :
			new IconButton(
				icon: const Icon(Icons.menu),
				onPressed: _openDrawer
			);

		if (useIos) {
			return new CupertinoNavigationBar(
				leading: primaryScreen ? openDrawer :
					new CupertinoButton(
						child: const Icon(Icons.arrow_back_ios),
						onPressed: () => Navigator.pop(context),
					),
				middle: title,
				trailing: primaryScreen ? popup : widget.action,
			);
		}

		return new AppBar(
			leading: primaryScreen ? openDrawer : null,
			title: title,
			actions: primaryScreen ? [popup] : widget.action != null ? [widget.action] : [],
		);
	}

	RefreshIndicator _wrapAroundRefresher(Widget inner) {
		return new RefreshIndicator(
			key: _refreshIndicatorKey,
			displacement: 20.0,
			child: inner,
			onRefresh: _onRefreshSwipe
		);
	}

	Widget _createContent() {
		switch (_currentPage) {
			case _ContentPage.LESSONS:
				return _wrapAroundRefresher(new LessonTimeline(widget.azuchath));
			case _ContentPage.HOMEWORK:
				return _wrapAroundRefresher(new HomeworkOverview(widget.azuchath));
			case _ContentPage.EXAMS:
				return _wrapAroundRefresher(new ExamsOverview(widget.azuchath));
			case _ContentPage.BULLETINS:
				return new BulletinScreen(widget.azuchath);
			case _ContentPage.MESSAGES:
				return new ConversationOverview(widget.azuchath);
		}

		return new Text("Coming soon?");
	}

	Widget _createFAB() {
		if (primaryScreen && (_currentPage == _ContentPage.LESSONS || _currentPage == _ContentPage.HOMEWORK)) {
			return new FloatingActionButton(
				child: const Icon(Icons.add),
				onPressed: showCreateHomework,
				tooltip: "Neue Hausaufgabe",
			);
		}

		return null;
	}

	DrawerItem _createItem(String content, IconData icon, _ContentPage page)
		=> new DrawerItem(content, icon, _changeContentFunction(page, context), selected: _currentPage == page);

  @override
  Widget build(BuildContext context) {
		var body =  primaryScreen ? _createContent() : widget.content;
		var appBar = _createAppBar(context);

		var drawer = new Drawer(
			child: new Container(
				padding: new EdgeInsets.only(
					top: MediaQuery.of(context).padding.top,
					left: 8.0,
				),
				child: new ListView(
					children: [
						new DrawerSubHeader("Inhalte"),
						_createItem("Unterricht", Icons.home, _ContentPage.LESSONS),
						_createItem("Hausaufgaben", Icons.assignment, _ContentPage.HOMEWORK),
						_createItem("Klausuren", Icons.edit, _ContentPage.EXAMS),
						_createItem("Aushänge", Icons.content_copy, _ContentPage.BULLETINS),
						new Divider(),

						new DrawerSubHeader("Kommunikation"),
						_createItem("Nachrichten (Beta)", Icons.send, _ContentPage.MESSAGES),
					],
				),
			)
		);

    return new Scaffold(
			key: _scaffoldKey,
			appBar: appBar,
			body: body,
			drawer: primaryScreen ? drawer : null,
			floatingActionButton: _createFAB(),
		);
  }
}

class DrawerItem extends StatelessWidget {

	static final Color textUnselected = Colors.black87;
	static final Color iconUnselected = Colors.black54;

	final String title;
	final IconData icon;
	final bool selected;
	final VoidCallback onClick;

	DrawerItem(this.title, this.icon, this.onClick, {this.selected = false});

  @override
  Widget build(BuildContext context) {
  	var selectedColor = Theme.of(context).primaryColor;
  	return new Container(
			height: 48.0,
		  child: new Material(
		  	color: selected ? Colors.black12 : null,
		  	child: new InkWell(
					onTap: onClick,
		  	  child: new Row(
		  	  	mainAxisSize: MainAxisSize.min,
		  	  	children: [
		  	  		new Container(margin: const EdgeInsets.only(right: 16.0),),
		  	  		new Icon(icon, size: 24.0, color: selected ? selectedColor : Colors.black54),
		  	  		new Container(margin: const EdgeInsets.only(right: 16.0),),
		  	  		new Text(title, style: new TextStyle(fontSize: 14.0, color: selected ? selectedColor : Colors.black87, fontWeight: FontWeight.w500)),
		  	  	],
		  	  ),
		  	)
		  ),
		);
  }
}

class DrawerSubHeader extends StatelessWidget {

	final String content;

	DrawerSubHeader(this.content);

  @override
  Widget build(BuildContext context) {
    return new Container(
			height: 56.0,
			padding: const EdgeInsets.only(left: 16.0),
			alignment: FractionalOffset.centerLeft,
			child: new Text(content, style: new TextStyle(fontSize: 14.0, color: Colors.black54, fontWeight: FontWeight.w500))
		);
  }
}

class HUSLoadingIndicator extends StatelessWidget {

  @override
  Widget build(BuildContext context) {
  	if (HUSScaffold.isIos()) {
			return new CupertinoActivityIndicator();
		} else {
  		return new CircularProgressIndicator();
		}
  }
}