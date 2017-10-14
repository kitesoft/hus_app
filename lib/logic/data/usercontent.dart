import 'package:azuchath_flutter/logic/data/auth.dart';
import 'package:azuchath_flutter/logic/data/lessons.dart';
import 'package:azuchath_flutter/logic/data/manager.dart';
import 'package:azuchath_flutter/utils.dart' as utils;

class PublicUserInfo {
	int id;
	String displayName;
	bool verified = false;

	PublicUserInfo(this.id, this.displayName, {this.verified});

	PublicUserInfo.fromUser(AuthenticatedUser user) : this(user.id, user.name);

	PublicUserInfo.fromMap(Map map) {
		id = map["id"];
		displayName = map["username"];
		if (map.containsKey("verified")) {
			verified = map["verified"];
		}
	}

	Map exportMap() {
		return {"id": id, "username": displayName, "verified": verified};
	}
}

enum HomeworkSyncStatus {
	/// Used to indicate that this homework has been locally created by the user
	/// and not yet been synced to the backend server.
	CREATED,
	/// Used to indicate that this homework exists on the server, but has local
	/// changes (for instance in its content or when its due) that have not yet
	/// been synced.
	EDITED,
	/// Used to indicate that this homework exists on the server, but has been
	/// deleted locally. The deletion has not yet been acknowledged by the server.
	DELETED,
	/// Used to indicate that this homework does not contain any local changes
	/// that could be uploaded to the server.
	SYNCED
}

class Homework {

	//Unique tags for hero animations
	Object heroCourse = new Object();

	static HomeworkSyncStatus byName(String name) {
		return {
			"CREATED": HomeworkSyncStatus.CREATED,
			"EDITED": HomeworkSyncStatus.EDITED,
			"DELETED": HomeworkSyncStatus.DELETED,
			"SYNCED": HomeworkSyncStatus.SYNCED
		}[name];
	}

	static String _toName(HomeworkSyncStatus s) {
		return {
			HomeworkSyncStatus.CREATED: "CREATED",
			HomeworkSyncStatus.EDITED: "EDITED",
			HomeworkSyncStatus.DELETED: "DELETED",
			HomeworkSyncStatus.SYNCED: "SYNCED"
		}[s];
	}

	int id;
	PublicUserInfo creator;
	Course course;

	DateTime due;
	String content;
	bool published;

	///An approximation provided by the creator on how long completing this
	///homework is going to take.
	int timeMin = 0;
	int timeMax = 0;

	bool completed;

	HomeworkSyncStatus syncStatus = HomeworkSyncStatus.SYNCED;
	bool completedSynced;

	Homework(this.id, this.creator, this.course, this.due, this.content, this.published, this.completed);

	Homework.fromMap(Map map, DataStorage storage, [alwaysRef = false]) {
		var hw = map["homework"];

		id = hw["id"];
		creator = new PublicUserInfo.fromMap(hw["creator"]);

		if (alwaysRef)
			course = storage.getCourseById(hw["course"]);
		else
			course = storage.handleCourse(new Course.fromData(hw["course"], storage));

		due = utils.formatDate.parseStrict(hw["due"]);
		content = hw["content"];
		var published = hw["published"];
		this.published = published == true || published == 1;

		completed = map["completed"];

		if (map.containsKey("completed_sync")) {
			completedSynced = map["completed_sync"];
			syncStatus = byName(map["sync_status"]);
		} else {
			//Assume that this is a freshly synced homework pulled from the server
			completedSynced = true;
			syncStatus = HomeworkSyncStatus.SYNCED;
		}

		if (hw.containsKey("time_min") && hw["time_min"] != null) {
			timeMin = hw["time_min"];
		}
		if (hw.containsKey("time_max") && hw["time_max"] != null) {
			timeMax = hw["time_max"];
		}
	}

	Map exportMap() {
		return {
			"homework": {
				"id": id,
				"creator": creator.exportMap(),
				"course": course.id,
				"due": utils.formatDate.format(due),
				"content": content,
				"published": published,
				"time_min": timeMin,
				"time_max": timeMax,
			},
			"completed": completed,
			"completed_sync": completedSynced,
			"sync_status": _toName(syncStatus)
		};
	}
}

class Exam {

	//Unique object for hero transitions
	Object heroTitle = new Object();

	int id;
	Course course;
	bool replacesLesson;

	String title;
	List<ExamTopic> topics;

	LessonTime start;
	LessonTime end;

	Exam.fromMap(Map map, DataStorage storage, [alwaysRef = false]) {
		id = map["id"];
		if (alwaysRef)
			course = storage.getCourseById(map["course"]);
		else
			course = storage.handleCourse(new Course.fromData(map["course"], storage));

		replacesLesson = map["replaces_lesson"];
		title = map["title"];
		
		var date = utils.formatDate.parseStrict(map["writing_date"]);
		start = new LessonTime(date, storage.getHourByNumber(map["hour_start"]));
		end = new LessonTime(date, storage.getHourByNumber(map["hour_end"]));

		topics = [];
		for (var t in map["topics"]) {
			topics.add(new ExamTopic.fromMap(t));
		}
	}

	double calcLearningProgress() {
		//TODO This needs to be better
		var sum = 0.0;

		for (var topic in topics) {
			if (topic.learned == ExamLearningStatus.WELL)
				sum += 3;
			if (topic.learned == ExamLearningStatus.MODERATE)
				sum += 1.75;
		}

		return sum / (3 * topics.length);
	}

	Map exportMap() {
		var topics = [];
		for (var t in this.topics) {
			topics.add(t.exportMap());
		}

		return {
			"id": id, "course": course.id, "replaces_lesson": replacesLesson,
			"title": title, "writing_date": utils.formatDate.format(start.date),
			"hour_start": start.hour.number, "hour_end": end.hour.number,
			"topics": topics
		};
	}
}

enum ExamLearningStatus {
	POOR, MODERATE, WELL
}

class ExamTopic {

	int id;

	String content;
	String explanation;

	ExamLearningStatus learned;
	String get learnedStr => _toStr(learned);

	bool learningChanged = false;

	ExamTopic.fromMap(Map map) {
		id = map["id"];
		content = map["content"];
		explanation = map["explanation"];
		learned = _fromStr(map["learned"]);

		if (map.containsKey("sync_learning")) {
			learningChanged = map["sync_learning"];
		}
	}

	Map exportMap() {
		return {
			"id": id, "content": content, "explanation": explanation,
			"learned": _toStr(learned), "sync_learning": learningChanged
		};
	}

	static ExamLearningStatus _fromStr(String str) {
		switch (str) {
			case "POOR": return ExamLearningStatus.POOR;
			case "MODERATE": return ExamLearningStatus.MODERATE;
			case "WELL": return ExamLearningStatus.WELL;
		}
		return null;
	}

	static String _toStr(ExamLearningStatus status) {
		switch (status) {
			case ExamLearningStatus.POOR: return "POOR";
			case ExamLearningStatus.MODERATE: return "MODERATE";
			case ExamLearningStatus.WELL: return "WELL";
		}
		return null;
	}
}