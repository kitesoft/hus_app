import 'dart:async';

import 'package:azuchath_flutter/logic/data/messages.dart';
import 'package:azuchath_flutter/logic/io/apiclient.dart';
import 'package:azuchath_flutter/logic/data/manager.dart';
import 'package:azuchath_flutter/logic/io/firebase.dart';
import 'package:azuchath_flutter/logic/io/synchronizer.dart';
import 'package:azuchath_flutter/logic/preferences.dart';
import 'package:azuchath_flutter/logic/timeline.dart';
import 'package:azuchath_flutter/utils.dart';

class Azuchath {

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