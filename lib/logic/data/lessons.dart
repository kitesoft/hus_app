import 'package:azuchath_flutter/logic/data/manager.dart';
import 'package:azuchath_flutter/logic/data/timeinfo.dart';
import 'package:azuchath_flutter/utils.dart';

class Week {
	int sequence;
	String name;

	Week(this.sequence, this.name);

	Week.fromData(Map map, DataStorage storage) {
		sequence = map["id"];
		name = map["name"];
	}

	static Week guessForDate(List<Week> weeks, List<TimeInfo> weekRefs, DateTime date) {
		if (weekRefs.isEmpty)
			return weeks[0];

		//Find monday of the week `date` lies in
		var monday = LessonTime.normDate(date);
		while (monday.weekday != DateTime.MONDAY) {
			monday = monday.subtract(const Duration(days: 1));
		}

		//Find a week reference to compare against. It should be near to `monday`
		//without starting in the future.
		var ref;
		var deltaWeeks;
		for (var av in weekRefs) {
			if (av.start.date.isAfter(monday)) //No future weeks allowed
				continue;

			var avDelta = monday.difference(av.start.date).inDays ~/ 7;
			if (deltaWeeks != null ? avDelta < deltaWeeks : true) {
				ref = av;
				deltaWeeks = avDelta;
			}
		}

		var weekIndex = weeks.firstWhere((w) => w.name == ref.name).sequence;

		var changeInWeeks = deltaWeeks % weeks.length;
		weekIndex += changeInWeeks;
		if (weekIndex > weeks.length - 1)
			weekIndex -= weeks.length;

		return weeks[weekIndex];
	}

	Map exportMap() {
		return {"id": sequence, "name": name};
	}

	@override
	String toString() {
		return "Week{$name}";
	}
}

class LocalTime {
	int hourOfDay;
	int minuteOfHour;

	LocalTime(this.hourOfDay, this.minuteOfHour);

	LocalTime.fromDate(DateTime time) {
		this.hourOfDay = time.hour;
		this.minuteOfHour = time.minute;
	}

	LocalTime.fromData(Map map, DataStorage storage) {
		hourOfDay = map["hour"];
		minuteOfHour = map["minute"];
	}

	bool isBefore(LocalTime time, [bool orEqual = false]) {
		if (hourOfDay < time.hourOfDay)
			return true;
		if (hourOfDay > time.hourOfDay)
			return false;

		if (minuteOfHour < time.minuteOfHour)
			return true;
		if (minuteOfHour > time.minuteOfHour)
			return false;

		return orEqual; //Same time
	}

	bool isAfter(LocalTime time, [bool orEqual = false]) {
		if (hourOfDay > time.hourOfDay)
			return true;
		if (hourOfDay < time.hourOfDay)
			return false;

		if (minuteOfHour > time.minuteOfHour)
			return true;
		if (minuteOfHour < time.minuteOfHour)
			return false;

		return orEqual; //Same time
	}

	DateTime atDate(DateTime time) => new DateTime(time.year, time.month, time.day, hourOfDay, minuteOfHour);
}

class LessonHour {
	int number;

	LocalTime start;
	LocalTime end;

	LessonHour(this.number, this.start, this.end);

	LessonHour.fromData(Map map, DataStorage storage) {
		number = map["hour"];

		start = new LocalTime(map["start_hour"], map["start_minute"]);
		end = new LocalTime(map["end_hour"], map["end_minute"]);
	}

	bool isBefore(LocalTime time) {
		return end.isBefore(time);
	}

	bool isDuring(LocalTime time) {
		return start.isBefore(time, true) && end.isAfter(time, true);
	}

	bool isAfter(LocalTime time) {
		return start.isAfter(time);
	}

	Map exportMap() {
		return {"hour": number,
			"start_hour": start.hourOfDay, "start_minute": start.minuteOfHour,
			"end_hour": end.hourOfDay, "end_minute": end.minuteOfHour};
	}

	@override
	String toString() {
		return "LessonHour{$number}";
	}
}

class Teacher {
	String abbreviation;
	String fullName;

	String get displayName => fullName ?? abbreviation;

	Teacher(this.abbreviation, this.fullName);

	Teacher.fromData(Map map, DataStorage storage) {
		abbreviation = map["abbrev"];
		fullName = map["name"];
	}

	Map exportMap() {
		return {"abbrev": abbreviation, "name": fullName};
	}

	@override
	String toString() {
		return "Teacher{$abbreviation}";
	}

	@override
	int get hashCode {
		int result = 17;
		result = 37 * result + abbreviation.hashCode;
		if (fullName != null)
			result = 37 * result + fullName.hashCode;
		return result;
	}

	@override
	bool operator ==(other) => (other is Teacher && other.abbreviation == abbreviation);
}

class Course {
	int id;

	String name;
	String subject;

	Teacher teacher;
	String formName;

	String get displayName => subject ?? name;

	Course(this.id, this.name, this.subject, this.teacher);

	Course.fromData(Map map, DataStorage storage, [alwaysRef = false]) {
		id = map["id"];
		name = map["name"];
		subject = map["subject"];

		if (map.containsKey("form_lcl")) {
			formName = map["form_lcl"];
		}

		if (alwaysRef)
			teacher = storage.getTeacherByAbbrev(map["teacher"]);
		else
			teacher = storage.handleTeacher(new Teacher.fromData(map["teacher"], storage));
	}

	Map exportMap() {
		return {"id": id, "name": name, "subject": subject, "teacher": teacher.abbreviation, "form_lcl": formName};
	}
}

class Lesson {
	Course course;
	int day;
	LessonHour start;
	LessonHour end;

	List<Week> weeks;
	String room;

	Lesson(this.course, this.day, this.start, this.end, this.weeks, this.room);

	Lesson.fromData(Map map, DataStorage storage, [alwaysRef = false]) {
		if (alwaysRef)
			course = storage.getCourseById(map["course"]);
		else
			course = storage.handleCourse(new Course.fromData(map["course"], storage));
		day = map["day"];
		start = storage.getHourByNumber(map["hour_start"]);
		end = storage.getHourByNumber(map["hour_end"]);

		weeks = new List<Week>();
		for (var week in map["weeks"]) {
			if (alwaysRef)
				weeks.add(storage.getWeekBySequence(week));
			else
				weeks.add(storage.handleWeek(new Week.fromData(week, storage)));
		}

		room = map["room"];
	}

	Map exportMap() {
		return {"course": course.id, "day": day, "hour_start": start.number,
			"hour_end": end.number, "weeks": new List.from(weeks.map((w) => w.sequence)),
			"room": room};
	}

	bool coversHour(LessonHour hour) => start.number <= hour.number && end.number >= hour.number;
}

class LessonTime {

	DateTime date;
	LessonHour hour;

	LessonTime(this.date, this.hour) {
		_normDate();
	}

	LessonTime.from(LessonTime other) : this(other.date, other.hour);

	LessonTime.findForDate(DateTime date, List<LessonHour> hours) {
		this.date = date;

		var time = new LocalTime.fromDate(date);
		//var lastH = hours[0];

		for (var h in hours) {
			if (h.isDuring(time)) {
				hour = h;
				break;
			}
			if (h.isAfter(time)) {
				/*We have two options that sort of make sense here. The problem is that
					we currently are between two school hours (for instance in breaks).
					We could return the last hour (for instance, in the first break
					between the 2nd and 3rd hour, we would return 2). That was the
					implementation for a long time. We changed it to return the next hour
					(in the previous example, hour 3) so that the timeline will focus on
					what's next.
					To change back to previous hour, change to hour = lastH and uncomment
					lastH = h;
				*/
				hour = h;
				break;
			}

			//lastH	= h;
		}

		if (hour == null) { //date is after the end of the last hour, use first hour of next day
 			this.date = date.add(new Duration(days: 1));
 			hour = hours[0];
		}

		_normDate();
	}

	void _normDate() {
		date = normDate(date);
	}

	/// Only returns the date of the given DateTime by settings hours and smaller
	/// units to 0.
	static DateTime normDate(DateTime date) {
		return new DateTime(date.year, date.month, date.day); //Ignore hour & smaller units
	}

	bool isBefore(LessonTime other, [bool orEqual = false]) {
		if (date.isBefore(other.date))
			return true;
		if (date.isAfter(other.date))
			return false;

		if (hour != null && other.hour != null) {
			if (hour.number < other.hour.number)
				return true;
			if (hour.number > other.hour.number)
				return false;
		} else if (hour == null) {
			if (other.hour != null)
				return true;
		} else if (other.hour == null) {
			if (hour != null)
				return false;
		}

		return orEqual;
	}

	bool isAfter(LessonTime other, [bool orEqual = false]) {
		if (date.isAfter(other.date))
			return true;
		if (date.isBefore(other.date))
			return false;

		if (hour != null && other.hour != null) {
			if (hour.number > other.hour.number)
				return true;
			if (hour.number < other.hour.number)
				return false;
		} else if (hour == null) {
			if (other.hour != null)
				return true;
		} else if (other.hour == null) {
			if (hour != null)
				return false;
		}

		return orEqual;
	}

	bool sameTimeAs(LessonTime other) {
		return other.date == date && other.hour.number == hour.number;
	}

	LessonTime previousTime(List<LessonHour> hours) {
		if (hour == null || hour == hours.first) { //Use previous day, last hour
			return new LessonTime(date.subtract(new Duration(days: 1)), hours.last);
		} else
			return new LessonTime(date, hours[hours.indexOf(hour) - 1]);
	}

	LessonTime nextTime(List<LessonHour> hours) {
		if (hour == null || hour == hours.last) { //Use next day, first hour
			return new LessonTime(date.add(new Duration(days: 1)), hours.first);
		} else
			return new LessonTime(date, hours[hours.indexOf(hour) + 1]);
	}

	@override
	String toString() {
		return "LessonTime{date=$date,hour=${hour.toString()}";
	}
}

enum SubstitutionType {
	CHANGE, ROOM_ONLY, REMOVED, EVENT, OTHER
}

class Substitution {

	static SubstitutionType parseSubstType(String str) {
		switch (str) {
			case "CHANGE": return SubstitutionType.CHANGE;
			case "ROOM_ONLY": return SubstitutionType.ROOM_ONLY;
			case "REMOVED": return SubstitutionType.REMOVED;
			case "EVENT": return SubstitutionType.EVENT;
			default: return SubstitutionType.OTHER;
		}
	}

	static String writeSubstType(SubstitutionType type) {
		return {
			SubstitutionType.CHANGE: "CHANGE", SubstitutionType.ROOM_ONLY: "ROOM_ONLY",
			SubstitutionType.REMOVED: "REMOVED", SubstitutionType.EVENT: "EVENT",
			SubstitutionType.OTHER: "OTHER"
		}[type];
	}

	LessonTime start;
	LessonTime end;

	SubstitutionType type;

	ChangedData<String> room;
	ChangedData<Course> course;

	Teacher substitute;

	String message;

	Substitution(this.start, this.end, this.type, [this.room, this.course, this.substitute, this.message]);

	Substitution.fromData(Map map, DataStorage storage, [alwaysRef = false]) {
		var date = formatDate.parseStrict(map["date"]);

		var hourStart = storage.getHourByNumber(map["hour_start"]);
		start = new LessonTime(date, hourStart);

		var hourEnd = storage.getHourByNumber(map["hour_end"]);
		end = new LessonTime(date, hourEnd);

		type = parseSubstType(map["type"]);

		var regRoom = map["room_regular"];
		var actRoom = map["room_actual"];
		room = new ChangedData<String>(regRoom, actRoom);

		Course regCourse, actCourse;
		if (alwaysRef) {
			if (map["course_regular"] != null)
				regCourse = storage.getCourseById(map["course_regular"]);
			if (map["course_actual"] != null)
				actCourse = storage.getCourseById(map["course_actual"]);

			if (map["teacher"] != null)
				substitute = storage.getTeacherByAbbrev(map["teacher"]);
		} else {
			if (map["course_regular"] != null)
				regCourse = storage.handleCourse(new Course.fromData(map["course_regular"], storage));
			if (map["course_actual"] != null)
				regCourse = storage.handleCourse(new Course.fromData(map["course_regular"], storage));

			if (map["teacher"] != null)
				substitute = storage.handleTeacher(new Teacher.fromData(map["teacher"], storage));
		}
		course = new ChangedData<Course>(regCourse, actCourse);

		message = map["message"];
	}

	Map exportMap() {
		return {
			"date": formatDate.format(start.date), "hour_start": start.hour.number,
			"hour_end": end.hour.number, "type": writeSubstType(type),
			"room_regular": room.regular, "room_actual": room.actual,
			"course_regular": course.regular?.id, "course_actual": course.actual?.id,
			"teacher": substitute?.abbreviation, "message": message
		};
	}
}