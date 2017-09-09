import 'package:azuchath_flutter/logic/data/lessons.dart';
import 'package:azuchath_flutter/logic/data/manager.dart';

import 'package:azuchath_flutter/utils.dart' as utils;

class TimeInfoType {

	static const TimeInfoType WEEK = const TimeInfoType._internal("WEEK");
	static const TimeInfoType HOLIDAY = const TimeInfoType._internal("HOLIDAY");
	static const TimeInfoType APPOINTMENT = const TimeInfoType._internal("APPOINTMENT");
	static const TimeInfoType INFO = const TimeInfoType._internal("INFO");

	final String name;

	static const List<TimeInfoType> ALL = const [WEEK, HOLIDAY, APPOINTMENT, INFO];

	static TimeInfoType findByName(String name) {
		for (var type in ALL) {
			if (type.name == name)
				return type;
		}

		return null;
	}

	const TimeInfoType._internal(this.name);

	bool interruptsLesson() => this == HOLIDAY || this == APPOINTMENT;
	bool shouldShowInTimeline() => this != WEEK;
}

class TimeInfo {

	int id;

	TimeInfoType type;
	String name;
	String message;

	LessonTime start;
	LessonTime end;

	TimeInfo(this.type, this.name, this.message, this.start, this.end);

	TimeInfo.fromData(Map map, DataStorage storage) {
		id = map["id"];
		type = TimeInfoType.findByName(map["type"]);
		name = map["name"];
		message = map["message"];

		var format = utils.formatDate;

		var startDate = format.parseStrict(map["start_date"]);
		var startHour = map["start_hour"];
		LessonHour parsedStart;
		if (startHour != null) {
			parsedStart = storage.getHourByNumber(startHour);
		}
		start = new LessonTime(startDate, parsedStart);

		var endDate = format.parseStrict(map["end_date"]);
		var endHour = map["end_hour"];
		LessonHour parsedEnd;
		if (endHour != null) {
			parsedEnd = storage.getHourByNumber(endHour);
		}
		end = new LessonTime(endDate, parsedEnd);
	}

	Map exportMap() {
		var format = utils.formatDate;

		return {"id": id, "type": type.name, "name": name, "message": message,
			"start_date": format.format(start.date), "start_hour": start?.hour?.number,
			"end_date": format.format(end.date), "end_hour": end?.hour?.number};
	}
}

class Bulletin {

	final int id;
	final String title;
	final String url;

	Bulletin(this.id, this.title, this.url);

	static Bulletin fromMap(Map map) {
		return new Bulletin(map["id"], map["title"], map["url"]);
	}
}