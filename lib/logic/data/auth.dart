import 'package:azuchath_flutter/logic/data/lessons.dart';
import 'package:azuchath_flutter/logic/data/manager.dart';

enum AccountType {
	STUDENT,
	TEACHER
}

class Session {

	String token;
	AuthenticatedUser user;

	Session(this.token, this.user);

	Session.fromData(Map map, DataStorage storage, [bool alwaysRef = false]) {
		token = map["token"];
		user = new AuthenticatedUser.fromData(map["user"], storage, alwaysRef);
	}

	Map exportMap() {
		return {"token": token, "user": user.exportMap()};
	}

}

class AuthenticatedUser {

	static AccountType parseAccountType(String str) {
		return {
			"STUDENT": AccountType.STUDENT,
			"TEACHER": AccountType.TEACHER,
		}[str];
	}

	static String formatAccountType(AccountType type) {
		return {
			AccountType.STUDENT: "STUDENT",
			AccountType.TEACHER: "TEACHER",
		}[type];
	}

	int id;
	String name;
	bool verified = false;

	AccountType type;

	List<Course> subscription;

	AuthenticatedUser(this.id, this.name, this.type, this.subscription);

	AuthenticatedUser.fromData(Map map, DataStorage storage, [bool alwaysRef = false]) {
		id = map["id"];
		name = map["name"];
		type = parseAccountType(map["type"]);

		if (map.containsKey("verified")) {
			verified = map["verified"];
		}

		subscription = new List<Course>();
		var coursesAr = map["courses"];
		for (var sub in coursesAr) {
			if (alwaysRef)
				subscription.add(storage.getCourseById(sub));
			else
				subscription.add(storage.handleCourse(new Course.fromData(sub, storage)));
		}
	}

	Map exportMap() {
		return {
			"id": id, "name": name, "type": formatAccountType(type),
			"verified": verified,
			"courses": new List.from(subscription.map((c) => c.id))
		};
	}
}

class Form {

	final int id;
	final String name;

	Form(this.id, this.name);

	Form.fromMap(Map map) : this (map["id"], map["name"]);
}