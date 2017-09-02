import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:azuchath_flutter/logic/data/auth.dart';
import 'package:azuchath_flutter/logic/data/lessons.dart';
import 'package:azuchath_flutter/logic/data/timeinfo.dart';
import 'package:azuchath_flutter/logic/data/usercontent.dart';
import 'package:path_provider/path_provider.dart';

class DataManager {

	DataStorage data;

	DatabaseManager io;

	bool ready = false;
	bool dirty = false;

	bool homeworkEdited = false;

	bool get isLoggedIn => data.session != null;

	Future init() async {
		//Find target file
		data = new DataStorage.empty();

		var dir = await getApplicationDocumentsDirectory();
		var file = new File("${dir.path}/azuchath_data.json");

		io = new DatabaseManager(file, this);

		if (!await file.exists()) {
			print("Creating local storage file");
			await file.create(recursive: true);
		} else {
			await io.readData();
		}

		ready = true;
	}

	bool isTimelineReady() {
		return data.schoolHours.isNotEmpty && data.weeks.isNotEmpty
				&& data.session != null;
	}

	void markDirty() {
		dirty = true;
	}

	void setHomeworkModified() {
		markDirty();
		homeworkEdited = true;
	}

	void saveIfDirty() {
		if (dirty)
			io.writeData();
	}
}

class DatabaseManager {

	File file;
	DataManager source;

	DatabaseManager(this.file, this.source) {
		print("Using ${file.path} as file to read / write local data");
	}

	Future readData() async {
		print("Starting to read local data");
		var json = await file.readAsString();
		if (json.isEmpty)
			return;

		Map data = JSON.decode(json);

		var storage = source.data;

		storage.weeks = new List.from(data["weeks"].map((w) => new Week.fromData(w, storage)));
		storage.schoolHours = new List.from(data["hours"].map((h) => new LessonHour.fromData(h, storage)));
		storage.teachers = new List.from(data["teachers"].map((t) => new Teacher.fromData(t, storage)));
		storage.courses = new List.from(data["courses"].map((c) => new Course.fromData(c, storage, true)));
		storage.lessons = new List.from(data["lessons"].map((l) => new Lesson.fromData(l, storage, true)));
		storage.substitutions = new List.from(data["substitutions"].map((s) => new Substitution.fromData(s, storage, true)));
		storage.timeInfo = new List.from(data["time_info"].map((t) => new TimeInfo.fromData(t, storage)));
		storage.homework = new List.from(data["homework"].map((hw) => new Homework.fromMap(hw, storage, true)));

		if (data.containsKey("session"))
			storage.session = new Session.fromData(data["session"], storage, true);

		if (data.containsKey("local_homework_changes"))
			source.homeworkEdited = data["local_homework_changes"];
	}

	Future writeData() async {
		print("Writing local data to file");
		var data = new Map();
		data["weeks"] = new List.from(source.data.weeks.map((w) => w.exportMap()));
		data["hours"] = new List.from(source.data.schoolHours.map((h) => h.exportMap()));
		data["teachers"] = new List.from(source.data.teachers.map((t) => t.exportMap()));
		data["courses"] = new List.from(source.data.courses.map((c) => c.exportMap()));
		data["lessons"] = new List.from(source.data.lessons.map((l) => l.exportMap()));
		data["substitutions"] = new List.from(source.data.substitutions.map((s) => s.exportMap()));
		data["time_info"] = new List.from(source.data.timeInfo.map((t) => t.exportMap()));
		data["homework"] = new List.from(source.data.homework.map((hw) => hw.exportMap()));
		if (source.data.session != null)
			data["session"] = source.data.session.exportMap();

		data["local_homework_changes"] = source.homeworkEdited;

		var json = JSON.encode(data);
		await file.writeAsString(json, mode: FileMode.WRITE);

		source.dirty = false;
	}
}

class DataStorage {

	Session session;

	List<Week> weeks;
	List<LessonHour> schoolHours;

	List<Teacher> teachers;

	List<Course> courses;
	List<Lesson> lessons;
	List<Substitution> substitutions;

	List<TimeInfo> timeInfo;
	List<Homework> homework;

	DataStorage(this.session, this.weeks, this.schoolHours, this.teachers, this.courses, this.lessons, this.timeInfo, this.substitutions);

	DataStorage.empty() {
		session = null;
		weeks = new List<Week>();
		schoolHours = new List<LessonHour>();
		teachers = new List<Teacher>();
		courses = new List<Course>();
		lessons = new List<Lesson>();
		substitutions = new List<Substitution>();
		timeInfo = new List<TimeInfo>();
		homework = new List<Homework>();
	}

	DataStorage.copyFrom(DataStorage other) {
		session = other.session;
		weeks = new List<Week>.from(other.weeks);
		schoolHours = new List<LessonHour>.from(other.schoolHours);
		teachers = new List<Teacher>.from(other.teachers);
		courses = new List<Course>.from(other.courses);
		lessons = new List<Lesson>.from(other.lessons);
		substitutions = new List<Substitution>.from(other.substitutions);
		timeInfo = new List<TimeInfo>.from(other.timeInfo);
		homework = new List<Homework>.from(other.homework);
	}

	Week getWeekBySequence(int sequence) => weeks.firstWhere((w)=>w.sequence == sequence, orElse: () => null);
	Week handleWeek(Week week) {
		var found = getWeekBySequence(week.sequence);
		if (found != null) {
			found.name = week.name;
			return found;
		}
		weeks.add(week);
		return week;
	}

	LessonHour getHourByNumber(int number) => schoolHours.firstWhere((h)=>h.number == number, orElse: () => null);
	LessonHour handleHour(LessonHour hour) {
		var found = getHourByNumber(hour.number);
		if (found != null) {
			found.start = hour.start;
			found.end = hour.end;
			return found;
		}
		schoolHours.add(hour);
		return hour;
	}

	Teacher getTeacherByAbbrev(String abbrev) => teachers.firstWhere((t) => t.abbreviation == abbrev, orElse: () => null);
	Teacher handleTeacher(Teacher teacher) {
		var found = getTeacherByAbbrev(teacher.abbreviation);
		if (found != null) {
			found.fullName = teacher.fullName;
			return found;
		}
		teachers.add(teacher);
		return teacher;
	}

	Course getCourseById(int id) => courses.firstWhere((c) => c.id == id, orElse: () => null);
	Course handleCourse(Course course) {
		var found = getCourseById(course.id);
		if (found != null) {
			found.name = course.name;
			found.teacher = handleTeacher(course.teacher);
			found.subject = course.subject;
			return found;
		}
		courses.add(course);
		return course;
	}
}