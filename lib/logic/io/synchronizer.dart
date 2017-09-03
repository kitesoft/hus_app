import 'dart:async';
import 'package:azuchath_flutter/logic/io/apiclient.dart';
import 'package:azuchath_flutter/logic/azuchath.dart';
import 'package:azuchath_flutter/logic/data/manager.dart';
import 'package:azuchath_flutter/logic/data/usercontent.dart';

class Synchronizer {

	Azuchath _azu;

	Set<SyncTargetType> toSync = new Set<SyncTargetType>();

	bool running = false;
	bool success = true;

	DataStorage storage;

	Synchronizer(this._azu);

	void _log(String msg) {
		print("[Synchronizer] $msg");
	}

	Future startSync([bool full = false]) async {
		try {
			storage = new DataStorage.copyFrom(_azu.data.data);
			running = true;
			await _identifyElements();

			if (running) {
				var i = 0;
				for (var target in toSync) {
					if (!running)
						break;

					_log("(${++i}/${toSync.length}): Synchronizing $target");
					await _syncTarget(target);
				}
			}

			if (success)
				await _azu.api.finishSynchronisation(toSync.toList());
		} catch (e, s) {
			print(e);
			print(s);
			success = false;
		}

		_finish();
	}

	Future _finish() async {
		_log("Done. Success = $success");
		running = false;

		if (success) {
			_log("Overriding local data");
			_azu.data.data = storage;
			await _azu.data.io.writeData();
			_azu.fireDataLoaded(new DataLoadedEvent());
		} else {
			print("Reporting unsuccessful sync.");
			_azu.fireDataLoaded(new DataLoadedEvent()..success=false);
		}
	}

	Future _identifyElements() async {
		_log("Starting by identifying which elements to update");

		var response = await _azu.api.startSynchronisation();
		if (!response.success) {
			running = false;
			success = false;
			_log("Could not identify what elements to update, cancelling sync.");
			_log("Error returned by server was ${response.describeErrorLog()}");

			if (response.error == GeneralServerError.INVALID_CREDENTIALS) {
				//The session we have locally is invalid, logout
				_log("Local sesssion is invalid, deleting it");
				_azu.data.data = new DataStorage.empty();
				_azu.data.markDirty();
			}
			return;
		}

		var targets = response.toSync;

		//Add forced elements
		if (_azu.data.homeworkEdited)
			targets.add(SyncTargetType.HOMEWORK);

		if (targets.contains(SyncTargetType.BASE_DATA)) {
			targets.add(SyncTargetType.TIMETABLE);
		}
		if (targets.contains(SyncTargetType.USER_SETTINGS)) {
			targets.add(SyncTargetType.TIMETABLE);
			targets.add(SyncTargetType.HOMEWORK);
			targets.add(SyncTargetType.EXAMS);
		}
		if (targets.contains(SyncTargetType.TIMETABLE)) {
			targets.add(SyncTargetType.SUBSTITUTIONS);
			targets.add(SyncTargetType.TIME_INFO);
		}

		//Sort and remove local, outdated data
		if (targets.contains(SyncTargetType.BASE_DATA)) {
			toSync.add(SyncTargetType.BASE_DATA);
			storage.weeks.clear();
			storage.schoolHours.clear();
		}
		if (targets.contains(SyncTargetType.USER_SETTINGS)) {
			toSync.add(SyncTargetType.USER_SETTINGS);
		}
		if (targets.contains(SyncTargetType.TIMETABLE)) {
			toSync.add(SyncTargetType.TIMETABLE);
			storage.lessons.clear();
		}
		if (targets.contains(SyncTargetType.SUBSTITUTIONS)) {
			toSync.add(SyncTargetType.SUBSTITUTIONS);
			storage.substitutions.clear();
		}
		if (targets.contains(SyncTargetType.TIME_INFO))
			toSync.add(SyncTargetType.TIME_INFO);

		if (targets.contains(SyncTargetType.HOMEWORK)) {
			toSync.add(SyncTargetType.HOMEWORK);
		}
		if (targets.contains(SyncTargetType.EXAMS)) {
			toSync.add(SyncTargetType.EXAMS);
			//TODO Fetch exams
		}

		_log("Found ${toSync.length} elements to sync: $toSync");
	}

	Future _syncTarget(SyncTargetType type) async {
		switch (type) {
			case SyncTargetType.BASE_DATA:
				await _syncBaseData();
				break;
			case SyncTargetType.USER_SETTINGS:
				await _syncUserSettings();
				break;
			case SyncTargetType.TIMETABLE:
				await _syncTimetable();
				break;
			case SyncTargetType.SUBSTITUTIONS:
				await _syncSubstitutions();
				break;
			case SyncTargetType.TIME_INFO:
				await _syncTimeInfo();
				break;
			case SyncTargetType.HOMEWORK:
				await _syncHomework();
				break;
			case SyncTargetType.EXAMS:
				await _syncExams();
				break;
		}
	}

	Future _syncBaseData() async {
		var res = await _azu.api.getSchoolInfo();
		if (res.success) {
			storage.weeks = res.weeks;
			storage.schoolHours = res.hours;
			_log("Done with base data (hours, weeks)");
		} else {
			_log("Could not update base data due to an server error: ${res.describeErrorLog()}");

			success = false;
			running = false;
		}
	}

	Future _syncUserSettings() async {
		var res = await _azu.api.getSessionInfo(storage);
		if (res.success) { //Response will write session into storage
			_log("Done with session (session, +courses, +teachers)");
		}
	}

	Future _syncTimetable() async {
		var res = await _azu.api.getTimetable(storage);
		if (res.success) { //Response will perform the writing into storage
			_log("Done with timetable (+teachers, +weeks, +courses, lessons)");
		} else {
			_log("Could not update timetable due to an server error: ${res.describeErrorLog()}");

			success = false;
			running = false;
		}
	}

	Future _syncSubstitutions() async {
		var res = await _azu.api.getSubstitutions(storage);
		if (res.success) {
			_log("Done with substitutions (+teachers, +courses, substitutions)");
		} else {
			_log("Could not update substitutions due to an server error: ${res.describeErrorLog()}");

			success = false;
			running = false;
		}
	}

	Future _syncTimeInfo() async {
		var res = await _azu.api.getTimeInfo(storage);
		if (res.success) {
			_log("Done with time info");
		} else {
			_log("Could not update time info due to an server error: ${res.describeErrorLog()}");

			success = false;
			running = false;
		}
	}

	Future _syncHomework() async {
		//First, identify what changes need to be uploaded to the server
		var createdNew = storage.homework.where((hw) => hw.syncStatus == HomeworkSyncStatus.CREATED);
		var contentChanged = storage.homework.where((hw) => hw.syncStatus == HomeworkSyncStatus.EDITED);
		var completionChanged = storage.homework.where((hw) => !hw.completedSynced);
		var deleted = storage.homework.where((hw) => hw.syncStatus == HomeworkSyncStatus.DELETED);

		for (var hw in createdNew) {
			await _azu.api.createHomework(hw);
		}
		for (var hw in contentChanged) {
			await _azu.api.editHomework(hw);
		}
		for (var hw in completionChanged) {
			await _azu.api.setHomeworkCompletion(hw);
		}
		for (var hw in deleted) {
			await _azu.api.deleteHomework(hw);
		}

		//After pushing the changes to the server, fetch a clean list of homework
		//that we consider to be in-sync
		var res = await _azu.api.fetchHomework(storage);
		if (res.success) {
			storage.homework = res.homework;
			_azu.data.homeworkEdited = false;
			_log("Done with homework");
		}
	}

	Future _syncExams() async {
		_log("Skip, not yet implemented");
	}
}