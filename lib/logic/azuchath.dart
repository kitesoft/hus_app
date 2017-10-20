import 'dart:async';
import 'dart:io';

import 'package:azuchath_flutter/logic/data/messages.dart';
import 'package:azuchath_flutter/logic/io/apiclient.dart';
import 'package:azuchath_flutter/logic/data/manager.dart';
import 'package:azuchath_flutter/logic/io/firebase.dart';
import 'package:azuchath_flutter/logic/io/synchronizer.dart';
import 'package:azuchath_flutter/logic/preferences.dart';
import 'package:azuchath_flutter/logic/timeline.dart';
import 'package:azuchath_flutter/utils.dart';

class Azuchath {

	///If the last refresh lays further behind than this duration, the app will
	///try to refresh the data available automatically.
	static const Duration _NO_REFRESH_MAX = const Duration(hours: 5);

	Stream<Duration> onNewFrame; //ui stuff, see main and chat_content for detail

	Stream<DataLoadedEvent> onDataLoaded;
	StreamController<DataLoadedEvent> _controller;

	FirebaseManager firebase;

	DataManager data;
	ApiClient api;
	LocalPreferences preferences;
	MessageManager messages;

	Timeline timeline;
	MinuteChangeListener _timeChangeListener;

	bool get ready => data != null ? data.ready : false;

	bool get timelineReady => timeline != null;

	Azuchath() {
		_controller = new StreamController<DataLoadedEvent>.broadcast();
		onDataLoaded = _controller.stream;
		_timeChangeListener = new MinuteChangeListener(_onMinuteChanged);
		_timeChangeListener.start();
	}

	void _onMinuteChanged() {
		if (timelineReady) {
			fireDataLoaded(new DataLoadedEvent()..simulated = true);
		}
	}

	Future start() async {
		if (ready)
			return;

		data = new DataManager();
		await data.init();

		preferences = new LocalPreferences();
		await preferences.loadFromFile();

		if (data.isTimelineReady())
			rebuildTimetable();

		api = new ApiClient(this);
		firebase = new FirebaseManager(this);
		await firebase.init();
		messages = new MessageManager(this);
		await messages.initLocal();
		connectWithChat();
	}

	///When the chat-client creates it message database, request push-notifications
	///from the user because on iOS, the introduction of chat comes with the same
	///version as push-notifications
	void handleMessageDbCreation() {
		if (Platform.isIOS && data.isLoggedIn)
			firebase.requestMsgPerms();
	}

	void _checkRefreshAutomatically() {
		var delta = new DateTime.now().difference(data.data.lastRefresh);
		if (delta >= _NO_REFRESH_MAX && data.data.session != null) {
			print("Starting refresh automatically");
			syncWithServer();
		}
	}

	void connectWithChat() {
		messages.startConnecting();
	}

	Future tearDown() async {
		await _controller.close();
		await messages.closeStream();
	}

	Future syncWithServer([bool full = false]) {
		return new Synchronizer(this).startSync(full);
	}

	void fireDataLoaded(DataLoadedEvent e) {
		if (data.isTimelineReady() && e.success)
			rebuildTimetable(!e.simulated);

	   _controller.add(e);
	}

	void rebuildTimetable([bool newDataAvailable = true]) {
		if (newDataAvailable) {
			print("Starting to rebuild timeline because of new data available!");
			var loader = new TimelinePopulator(this);
			loader.build(21);
			timeline = loader.result;
		} else {
			var updater = new TimelineChanger(this);
			updater.updateTimeline();
			timeline = updater.result;
		}
	}

	void onAppInBackground() {
		messages.close();
		data.saveIfDirty();

		if (_timeChangeListener.isRunning())
			_timeChangeListener.pause();
	}

	void onAppInForeground() {
		_checkRefreshAutomatically();

		if (!messages.connected)
			messages.initLocal().then((_) => messages.startConnecting());

		if (!_timeChangeListener.isRunning() && timelineReady)
			_timeChangeListener.start();
	}
}

class DataLoadedEvent {

	bool success = true;
	bool simulated = false;

}