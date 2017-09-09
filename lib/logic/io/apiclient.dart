import 'dart:async';
import 'dart:convert';
import 'dart:io' as io;

import 'package:azuchath_flutter/logic/azuchath.dart';
import 'package:azuchath_flutter/logic/data/auth.dart';
import 'package:azuchath_flutter/logic/data/lessons.dart';
import 'package:azuchath_flutter/logic/data/manager.dart';
import 'package:azuchath_flutter/logic/data/timeinfo.dart';
import 'package:azuchath_flutter/logic/data/usercontent.dart';
import 'package:azuchath_flutter/utils.dart' as utils;
import 'package:http/http.dart';

class AzuHttpClient extends BaseClient {

	static const String _USER_AGENT = "Azuchath Flutter App, Version 1 (0.0.1 Beta)";

	final Client _inner;
	final Azuchath _azu;

	AzuHttpClient(this._inner, this._azu);

	Future<StreamedResponse> send(BaseRequest request) {
		request.headers['User-Agent'] = _USER_AGENT;
		if (_azu.data.data.session != null)
			request.headers['Authorization'] = "Token ${_azu.data.data.session.token}";
		request.headers["X-Api-Version"] = "1";
		return _inner.send(request);
	}
}

class ApiClient {

	static const String _BASE = "https://api.tutorialfactory.org";

	io.HttpClient client;
	Client http;

	ApiClient(Azuchath azu) {
		client = new io.HttpClient();
		http = new AzuHttpClient(new IOClient(client), azu);
	}

	void shutdown() {
		client.close(force: true);
	}

	Uri _getUrl(String path) => Uri.parse(_BASE + path);

	Future<SchoolInfoResponse> getSchoolInfo() async {
		var response = await http.get(_getUrl("/about/school"));

		var res = new SchoolInfoResponse(false);
		await res.populate(response);
		return res;
	}

	Future<SessionInfoResponse> getSessionInfo([DataStorage data]) async {
		var response = await http.get(_getUrl("/auth/session"));

		var res = new SessionInfoResponse(false, data ?? new DataStorage.empty());
		await res.populate(response);
		return res;
	}

	Future<GenericStatusResponse> writeFcmToken(String token) async {
		var response = await http.put(_getUrl("/auth/session/fcm_token"), body: {
			"fcm": token
		});

		var res = new GenericStatusResponse(false);
		await res.populate(response);
		return res;
	}

	Future<LoginResponse> loginWithPassword(String username, String password) async {
		var response = await http.post(_getUrl("/auth/login/password"), body: {
			"username": username, "password": password
		});

		var res = new LoginResponse();
		await res.populate(response);
		return res;
	}

	Future<RegisterResponse> register(String mail, String name, String password, String verification) async {
		var response = await http.post(_getUrl("/auth/register/password"), body: {
			"mail": mail, "password": password, "name": name, "verification": verification
		});

		var res = new RegisterResponse();
		await res.populate(response);
		return res;
	}

	Future<Null> logout() async {
		await http.delete(_getUrl("/auth/session"));
	}

	Future<TimetableResponse> getTimetable([DataStorage data]) async {
		var response = await http.get(_getUrl("/timetable/mine"));

		var res = new TimetableResponse(false, data ?? new DataStorage.empty());
		await res.populate(response);
		return res;
	}

	Future<SubstitutionResponse> getSubstitutions([DataStorage data]) async {
		var response = await http.get(_getUrl("/substitutions/mine"));

		var res = new SubstitutionResponse(false, data ?? new DataStorage.empty());
		await res.populate(response);
		return res;
	}

	Future<TimeInfoResponse> getTimeInfo([DataStorage data]) async {
		var response = await http.get(_getUrl("/time/for_me"));

		var res = new TimeInfoResponse(false, data ?? new DataStorage.empty());
		await res.populate(response);
		return res;
	}

	Future<SyncStartResponse> startSynchronisation() async {
		var response = await http.get(_getUrl("/sync/start"));

		var res = new SyncStartResponse(false);
		await res.populate(response);
		return res;
	}

	Future<SyncFinishResponse> finishSynchronisation(List<SyncTargetType> finished) async {
		if (finished.isEmpty)
			return new SyncFinishResponse(true);

		var targets = finished.join(";");
		var response = await http.post(_getUrl("/sync/report"), body: {"targets": targets});

		var res = new SyncFinishResponse(false);
		await res.populate(response);
		return res;
	}

	Future<HomeworkListResponse> fetchHomework(DataStorage ref) async {
		var response = await http.get(_getUrl("/homework"));

		var res = new HomeworkListResponse(false, ref);
		await res.populate(response);
		return res;
	}

	Future<GenericStatusResponse> createHomework(Homework hw) async {
		var response = await http.post(_getUrl("/homework"), body: {
			"course": hw.course.id.toString(), "due": utils.formatDate.format(hw.due),
			"content": hw.content, "publish": hw.published.toString(),
			"time_min": hw.timeMin.toString(), "time_max": hw.timeMax.toString()
		});

		var res = new GenericStatusResponse(false);
		await res.populate(response);
		return res;
	}

	Future<GenericStatusResponse> editHomework(Homework hw) async {
		var response = await http.put(_getUrl("/homework/${hw.id}"), body: {
			"due": utils.formatDate.format(hw.due), "content": hw.content,
			"publish": hw.published.toString(), "time_min": hw.timeMin.toString(), "time_max": hw.timeMax.toString()
		});

		var res = new GenericStatusResponse(false);
		await res.populate(response);
		return res;
	}

	Future<GenericStatusResponse> deleteHomework(Homework hw) async {
		var response = await http.delete(_getUrl("/homework/${hw.id}"));

		var res = new GenericStatusResponse(false);
		await res.populate(response);
		return res;
	}

	Future<GenericStatusResponse> setHomeworkCompletion(Homework hw) async {
		var response = await http.put(_getUrl("/homework/${hw.id}/status"), body: {
			"completed": hw.completed.toString()
		});

		var res = new GenericStatusResponse(false);
		await res.populate(response);
		return res;
	}

	Future<FormListResponse> getAllForms() async {
		var response = await http.get(_getUrl("/subscription/forms"));

		var res = new FormListResponse(false);
		await res.populate(response);
		return res;
	}

	Future<CoursesInFormResponse> getCoursesInForm(Form f, [DataStorage storage]) async {
		var response = await http.get(_getUrl("/subscription/courses?form=${f.id}"));

		var res = new CoursesInFormResponse(false);
		res.storage = storage ?? new DataStorage.empty();
		await res.populate(response);
		return res;
	}

	Future<SetSubscriptionResponse> setSubscription(Form f, List<Course> subscription) async {
		var coursesStr = subscription.map((c) => c.id).join(",");

		var response = await http.put(_getUrl("/subscription"), body: {
			"form": f.id.toString(),
			"courses": coursesStr
		});

		var res = new SetSubscriptionResponse(false);
		await res.populate(response);
		return res;
	}

	Future<BulletinResponse> getBulletins() async {
		var response = await http.get(_getUrl("/bulletins"));

		var res = new BulletinResponse(false);
		await res.populate(response);
		return res;
	}
}

enum GeneralServerError {
	INVALID_CREDENTIALS
}

abstract class ServerResponse {

	bool success;
	GeneralServerError error;

	ServerResponse(this.success);

	Future populate(Response res);

	String describeErrorLog() => "nothing :(";

	void _parseError(Response res) {
		print(res.body);
		if (res.statusCode == 401) {
			if (JSON.decode(res.body)["error"] == "notAuthorized")
				error = GeneralServerError.INVALID_CREDENTIALS;
		}
	}
}

class SyncTargetType {

	static const SyncTargetType BASE_DATA = const SyncTargetType._internal("BASE_DATA");
	static const SyncTargetType TIMETABLE = const SyncTargetType._internal("TIMETABLE");
	static const SyncTargetType SUBSTITUTIONS = const SyncTargetType._internal("SUBSTITUTIONS");
	static const SyncTargetType TIME_INFO = const SyncTargetType._internal("TIME_INFO");
	static const SyncTargetType HOMEWORK = const SyncTargetType._internal("HOMEWORK");
	static const SyncTargetType EXAMS = const SyncTargetType._internal("EXAMS");
	static const SyncTargetType USER_SETTINGS = const SyncTargetType._internal("USER_SETTINGS");

	static const List<SyncTargetType> _ALL = const [BASE_DATA, TIMETABLE, SUBSTITUTIONS, TIME_INFO, HOMEWORK, EXAMS, USER_SETTINGS];

	static SyncTargetType findByName(String name) {
		for (var type in _ALL) {
			if (type.name == name)
				return type;
		}

		return null;
	}

	final String name;

	const SyncTargetType._internal(this.name);

	@override
	String toString() => name;
}

class SyncStartResponse extends ServerResponse {

	Set<SyncTargetType> toSync;

  SyncStartResponse(bool success) : super(success) {
  	toSync = new Set<SyncTargetType>();
	}

	@override
  Future populate(Response res) async {
  	success = res.statusCode == 200;

		if (success) {
			List<String> ar = JSON.decode(res.body);

			for (String el in ar) {
				var type = SyncTargetType.findByName(el);
				if (type != null)
					toSync.add(type);
			}
		} else
			_parseError(res);
	}
}

class SyncFinishResponse extends ServerResponse {

	SyncFinishResponse(bool success) : super(success);

  @override
  Future populate(Response res) async {
    success = res.statusCode == 200;
    //Does not contain any additional data
		if (!success)
			_parseError(res);
  }
}

class SessionInfoResponse extends ServerResponse {

	DataStorage _result;
	Session get session => _result.session;

  SessionInfoResponse(bool success, DataStorage ref) : super(success) {
  	_result = ref;
	}

  @override
  Future populate(Response res) async {
  	success = res.statusCode == 200;

  	if (success) {
			var obj = JSON.decode(res.body);
			_result.session = new Session.fromData(obj, _result);
		} else
  		_parseError(res);
  }
}

class LoginResponse extends SessionInfoResponse {

	LoginResponse() : super(false, new DataStorage.empty());

}

class RegisterResponse extends SessionInfoResponse {

	static const int FAILURE_INVALID_MAIL = 0;
	static const int FAILURE_USER_EXISTS = 1;
	static const int FAILURE_INVALID_VERIFICATION = 2;

	int failureReason;

	RegisterResponse() : super(false, new DataStorage.empty());

	@override
	Future populate(Response res) async {
		success = res.statusCode == 200;
		if (success) {
			await super.populate(res);
		} else {
			try {
				var obj = JSON.decode(res.body);
				if (obj["error"] == "invalidMail")
					failureReason = FAILURE_INVALID_MAIL;
				else if (obj["error"] == "alreadyExisting")
					failureReason = FAILURE_USER_EXISTS;
				else if (obj["error"] == "forbidden")
					failureReason = FAILURE_INVALID_VERIFICATION;
				else
					super._parseError(res);
			} catch (e) {
				super._parseError(res);
			}
		}
	}

}

class SchoolInfoResponse extends ServerResponse {

	List<Week> weeks;
	List<LessonHour> hours;

	SchoolInfoResponse(bool success) : super(success) {
		weeks = new List<Week>();
		hours = new List<LessonHour>();
	}

  @override
  Future populate(Response res) async {
		success = res.statusCode == 200;

		var data = new DataStorage.empty();

		if (success) {
			var obj = JSON.decode(res.body);

			var weeks = obj["weeks"];
			for (var week in weeks) {
				data.weeks.add(new Week.fromData(week, data));
			}

			var hours = obj["hours"];
			for (var hour in hours) {
				data.schoolHours.add(new LessonHour.fromData(hour, data));
			}

			this.weeks = data.weeks;
			this.hours = data.schoolHours;
		} else
			_parseError(res);
  }
}

class TimetableResponse extends ServerResponse {

	DataStorage result;

	List<Lesson> get lessons => result.lessons;

	TimetableResponse(bool success, DataStorage reference) : super(success) {
		result = reference;

		result.lessons.clear();
	}

  @override
  Future populate(Response res) async {
  	success = res.statusCode == 200;

  	if (success) {
  		var ar = JSON.decode(res.body);

  		for (var lesson in ar) {
  			var l = new Lesson.fromData(lesson, result); //Will write teacher and course

				//form of course will only be set for teachers in timetable response
				l.course.formName = lesson["course"]["form"];

  			result.lessons.add(l);
			}
		} else
			_parseError(res);
  }
}

class SubstitutionResponse extends ServerResponse {

	DataStorage _result;
	List<Substitution> get substitutions => _result.substitutions;

  SubstitutionResponse(bool success, DataStorage reference) : super(success) {
  	_result = reference;

  	_result.substitutions.clear();
	}

  @override
  Future populate(Response res) async {
    success = res.statusCode == 200;

    if (success) {
    	var ar = JSON.decode(res.body);

    	for (var subst in ar) {
    		var s = new Substitution.fromData(subst, _result);
    		_result.substitutions.add(s);
			}
		}
  }

}

class TimeInfoResponse extends ServerResponse {

	DataStorage result;

	List<TimeInfo> get info => result.timeInfo;

  TimeInfoResponse(bool success, DataStorage reference) : super(success) {
  	result = reference;
  	result.timeInfo.clear();
	}

  @override
  Future populate(Response res) async {
		success = res.statusCode == 200;

		if (success) {
			var ar = JSON.decode(res.body);

			for (var timeInfo in ar) {
				var ti = new TimeInfo.fromData(timeInfo, result);
				result.timeInfo.add(ti);
			}
		} else
			_parseError(res);
  }
}

class HomeworkListResponse extends ServerResponse {

	DataStorage _ref;
	List<Homework> homework = new List<Homework>();

  HomeworkListResponse(bool success, this._ref) : super(success);

  @override
  Future populate(Response res) async {
    success = res.statusCode == 200;

    if (success) {
    	var ar = JSON.decode(res.body);

    	for (var hw in ar) {
				homework.add(new Homework.fromMap(hw, _ref));
			}
		}
  }
}

class GenericStatusResponse extends ServerResponse {

  GenericStatusResponse(bool success) : super(success);

  @override
  Future populate(Response res) async {
    success = res.statusCode == 200 || res.statusCode == 204;
    if (!success)
    	_parseError(res);
  }
}

class FormListResponse extends ServerResponse {

  FormListResponse(bool success) : super(success);

  List<Form> forms = new List<Form>();

  @override
  Future populate(Response res) async {
    success = res.statusCode == 200;

    if (success) {
    	var ar = JSON.decode(res.body);

    	for (var form in ar)
				forms.add(new Form.fromMap(form));

    	forms.sort((f1, f2) => f1.name.compareTo(f2.name));
		} else {
    	_parseError(res);
		}
  }
}

class CoursesInFormResponse extends ServerResponse {

  CoursesInFormResponse(bool success) : super(success);

  List<Course> courses = new List<Course>();
  DataStorage storage;

  @override
  Future populate(Response res) async {
  	success = res.statusCode == 200;

  	if (success) {
  		var ar = JSON.decode(res.body);

  		for (var course in ar)
  			courses.add(storage.handleCourse(new Course.fromData(course, storage)));
		} else {
			_parseError(res);
		}
  }
}

class SetSubscriptionResponse extends ServerResponse {

  SetSubscriptionResponse(bool success) : super(success);

  List<Course> subscription = new List<Course>();
  List<String> invalid;

  @override
  Future populate(Response res) async {
		success = res.statusCode == 200;

		var data = new DataStorage.empty();

		if (success) {
			var obj = JSON.decode(res.body);

			var courses = obj["courses"];
			for (var c in courses) {
				subscription.add(new Course.fromData(c, data));
			}

			var invalid = obj["invalid"];
			this.invalid = new List<String>.from(invalid);
		} else {
			_parseError(res);
		}
  }
}

class BulletinResponse extends ServerResponse {

	BulletinResponse(bool success) : super(success);

	List<Bulletin> bulletins = new List<Bulletin>();

	@override
	Future populate(Response res) async {
		success = res.statusCode == 200;

		if (success) {
			var ar = JSON.decode(res.body);

			for (var b in ar) {
				bulletins.add(Bulletin.fromMap(b));
			}
		} else {
			_parseError(res);
		}
	}
}