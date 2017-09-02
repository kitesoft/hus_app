import 'package:azuchath_flutter/logic/data/auth.dart';
import 'package:azuchath_flutter/logic/data/lessons.dart';
import 'package:azuchath_flutter/logic/data/manager.dart';
import 'package:azuchath_flutter/utils.dart' as utils;

class PublicUserInfo {
	int id;
	String displayName;

	PublicUserInfo(this.id, this.displayName);

	PublicUserInfo.fromUser(AuthenticatedUser user) : this(user.id, user.name);

	PublicUserInfo.fromMap(Map map) {
		id = map["id"];
		displayName = map["username"];
	}

	Map exportMap() {
		return {"id": id, "username": displayName};
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
	}

	Map exportMap() {
		return {
			"homework": {
				"id": id,
				"creator": creator.exportMap(),
				"course": course.id,
				"due": utils.formatDate.format(due),
				"content": content,
				"published": published
			},
			"completed": completed,
			"completed_sync": completedSynced,
			"sync_status": _toName(syncStatus)
		};
	}
}