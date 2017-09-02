import 'dart:async';
import 'dart:convert';

import 'dart:io';

import 'package:path_provider/path_provider.dart';

enum LessonTimeMode {
	///Show numbers (1-13) for time
	SCHOOL_HOUR,
	///Show the exact time (start / end) for lessons when they start / end
	EXACT_TIME
}

class LocalPreferences {

	LessonTimeMode timeMode = LessonTimeMode.EXACT_TIME;
	///Whether to show a time indicator for the next lesson giving a hint of how
	///much time is left before the lesson starts.
	bool showNextTimeIndicator = true;

	bool showFreePeriod = false;

	Future<Null> loadFromFile() async {
		var dir = await getApplicationDocumentsDirectory();
		var file = new File("${dir.path}/preferences.json");

		if (!await file.exists()) {
			await file.create(recursive: true);
		}

		var content = await file.readAsString();
		if (content.isEmpty)
			return;

		Map json = JSON.decode(content);
		timeMode = json["time_mode"] == 0 ?
					LessonTimeMode.SCHOOL_HOUR : LessonTimeMode.EXACT_TIME;
		showNextTimeIndicator = json["show_time_indicator"];

		if (json.containsKey("show_free_period")) {
			showFreePeriod = json["show_free_period"];
		}
	}

	Future<Null> saveToFile() async {
		var dir = await getApplicationDocumentsDirectory();
		var file = new File("${dir.path}/preferences.json");

		if (!await file.exists()) {
			await file.create(recursive: true);
		}

		var json = new Map();
		json["time_mode"] = timeMode == LessonTimeMode.SCHOOL_HOUR ? 0 : 1;
		json["show_time_indicator"] = showNextTimeIndicator;
		json["show_free_period"] = showFreePeriod;

		await file.writeAsString(JSON.encode(json), flush: true);
	}
}