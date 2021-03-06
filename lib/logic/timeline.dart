import 'package:azuchath_flutter/logic/azuchath.dart';
import 'package:azuchath_flutter/logic/data/auth.dart';
import 'package:azuchath_flutter/logic/data/lessons.dart';
import 'package:azuchath_flutter/logic/data/timeinfo.dart';
import 'package:azuchath_flutter/logic/data/usercontent.dart';
import 'package:azuchath_flutter/utils.dart';

abstract class TimelineEntry {

	final LessonTime start;
	final LessonTime end;

  TimelineEntry(this.start, this.end);

}

class CourseSelectionSuggestion extends TimelineEntry {

	CourseSelectionSuggestion(LessonTime time) : super(time, time);

}

class DaySeparator extends TimelineEntry {

	Week week;

	DaySeparator(LessonTime time, this.week) : super(time, time);

}

class LessonEntry extends TimelineEntry {

	bool substitution = false;
	bool removed = false;
	Teacher teacher;

	ChangedData<Course> course;
	ChangedData<String> room;

	String message;
	Exam exam;

	LessonEntry.fromRegularLesson(LessonTime start, LessonTime end, Lesson l) : super(start, end) {
		substitution = false;
		removed = false;
		teacher = l.course.teacher;
		course = new ChangedData<Course>.onlyRegular(l.course);
		room = new ChangedData<String>.onlyRegular(l.room);
	}

	LessonEntry.fromSubstitution(Substitution s) : super(s.start, s.end) {
		substitution = true;
		removed = s.type == SubstitutionType.REMOVED;
		teacher = s.substitute;
		course = s.course;
		room = s.room;
		message = s.message;
	}

  LessonEntry(LessonTime start, LessonTime end) : super(start, end);
}

class TimeInformationEntry extends TimelineEntry {

	TimeInfo entry;

	TimeInformationEntry(this.entry) : super (entry.start, entry.end);
}

class FreePeriodEntry extends TimelineEntry {

	FreePeriodEntry(LessonTime start, LessonTime end) : super(start, end);

}

class Timeline {

	List<TimelineEntry> entries = new List<TimelineEntry>();

	Timeline();
	Timeline.copy(Timeline other) {
		entries = new List<TimelineEntry>.from(other.entries);
	}

	List<LessonEntry> findLessonsForCourse(Course c) {
		var entries = new List<LessonEntry>();

		for (var e in this.entries) {
			if (e is LessonEntry) {
				if (e.course.actual == c || e.course.regular == c)
					entries.add(e);
			}
		}

		return entries;
	}

	List<Homework> findHomeworkForLesson(LessonEntry entry, List<Homework> allHw) {
		var hw = new List<Homework>();

		for (var e in allHw) {
			if (e.course == entry.course.current && e.due == entry.start.date && e.syncStatus != HomeworkSyncStatus.DELETED)
				hw.add(e);
		}

		return hw;
	}
}

class _TimelineDuration implements Comparable<_TimelineDuration> {

	static const int TYPE_INTERRUPTION = 0;
	static const int TYPE_REGULAR = 1;

	int type;

	List<TimelineEntry> entries = new List<TimelineEntry>();

	//both times are included in this duration
	LessonTime start;
	LessonTime end;

	_TimelineDuration(this.type, this.start, this.end);

	bool covers(LessonTime time) => start.isBefore(time, true) && end.isAfter(time, true);

	LessonTime lastBefore(List<LessonHour> hours) => start.previousTime(hours);

	LessonTime firstAfter(List<LessonHour> hours) => end.nextTime(hours);
	
  @override
  int compareTo(_TimelineDuration other) => start.isBefore(other.start) ? -1 : (start.isAfter(other.start) ? 1 : 0 );
}

class _TimelineInfoEntry {
	bool included = false;

	TimeInfo info;

	_TimelineInfoEntry(this.info);
}

class TimelineChanger {

	Azuchath azuchath;
	Timeline result;

	Timeline _source;

	TimelineChanger(this.azuchath) {
		_source = azuchath.timeline;
		result = new Timeline.copy(_source);
	}

	void updateTimeline() {
		//An timeline update without new data occurs on each time (minute) change on
		//the system. As there is no new data, all we have to do with the original
		//timeline is filter out entries from past.
		clearWithoutDaySeps();
		removeEmptyDaySeps();
	}

	void clearWithoutDaySeps() {
		var hours = azuchath.data.data.schoolHours;

		var now = new LessonTime.findForDate(new DateTime.now(), hours);

		for (var entry in _source.entries) {
			if (entry is DaySeparator)
				continue;

			//if end hour is null, it goes on all day -> won't be removed
			if (entry.end?.hour == null)
				continue;

			if (entry.end.isBefore(now)) {
				result.entries.remove(entry);
				/*No return here. Non-interrupting time-entries affecting a span of
				* time are displayed before any lessons at the same time. This means
				* that a card might be outdated but a card appearing earlier is not.*/
			}
		}

		//Copy so that further operations can use the current state
		_source.entries = result.entries;
	}

	void removeEmptyDaySeps() {
		//Mark the last separator. If directly followed by another one, remove first
		var lastSep;

		for (var entry in _source.entries) {
			if (entry is DaySeparator) {
				if (lastSep != null) {
					result.entries.remove(lastSep);
				}

				lastSep = entry;
			} else
				lastSep = null;
		}
	}
}

class TimelinePopulator {

	Azuchath source;
	Timeline result;

	List<_TimelineDuration> durations = new List<_TimelineDuration>();
	List<_TimelineInfoEntry> infoEntries = new List<_TimelineInfoEntry>();

	List<TimeInfo> holidays; //TimeEntries that interrupt lessons
	List<TimeInfo> weeks; //TimeEntries that define weeks
	List<TimeInfo> info; //TimeEntries that should result in info-cards

	LessonTime currentTime;

	TimelinePopulator(this.source) {
		result = new Timeline();
	}

	void build(int days) {
		currentTime = new LessonTime.findForDate(new DateTime.now(), source.data.data.schoolHours);
		/*
			The algorithm to determine the content of the timetable displays basically
			works in 3 steps:
				1: Find all durations with no regular lessons (holidays or appointments)
				2: Find substitutions (not currently implemented)
				3: Fill all empty space with regular lessons from the timetable
		*/
		prepare(); //Collect and identify given data

		_findHolidayDurations();
		_findSubstitutions();
		_findExams();
		_fillRest(days);

		_finishAggregation();
	}

	void prepare() {
		var all = source.data.data.timeInfo;

		holidays = new List<TimeInfo>.from(all.where((e) => e.type.interruptsLesson()));
		weeks = new List<TimeInfo>.from(all.where((e) => e.type == TimeInfoType.WEEK));
		info = new List<TimeInfo>.from(all.where((e) => e.type == TimeInfoType.INFO));
	}

	void _findHolidayDurations() {
		for (var h in holidays) {
			if (currentTime.isAfter(h.end))
				continue; //Holiday is outdated, should not yield a duration then

			var dur = new _TimelineDuration(_TimelineDuration.TYPE_INTERRUPTION, h.start, h.end);
			dur.entries.add(new TimeInformationEntry(h));
			durations.add(dur);
		}

		for (var i in info) {
			if (currentTime.isAfter(i.end))
				continue;

			infoEntries.add(new _TimelineInfoEntry(i));
		}
	}

	void _findSubstitutions() {
		for (var sub in source.data.data.substitutions) {
			if (currentTime.isAfter(sub.end))
				continue; //Substitution outdated

			var dur = new _TimelineDuration(_TimelineDuration.TYPE_INTERRUPTION, sub.start, sub.end);
			dur.entries.add(new LessonEntry.fromSubstitution(sub));
			durations.add(dur);
		}
	}

	void _findExams() {
		for (var exam in source.data.data.exams) {
			if (currentTime.isAfter(exam.end))
				continue;

			bool attached = false;
			//Is there a substitution covering this exact duration. If so, attach this
			//exam to that substitution's entry
			for (var dur in durations) {
				if (dur.entries.length != 1)
					continue;

				if (!(dur.entries.first is LessonEntry))
					continue;

				if (dur.start.sameTimeAs(exam.start) && dur.end.sameTimeAs(exam.end)) {
					LessonEntry entry = dur.entries.first;
					entry.exam = exam;
					attached = true;
					break;
				}
			}

			if (!attached) {
				//Ok, looks like we'll need to create another entry. In order to find
				//teacher and room, we query all regular lessons during the time the
				//exam will be written, find the one with the same course, and steal its
				//data.
				var dur = new _TimelineDuration(_TimelineDuration.TYPE_INTERRUPTION, exam.start, exam.end);
				List<TimelineEntry> regularEntries = _findRegularLessons(dur, lessonsOnly: true);

				for (var entry in regularEntries) {
					if (!(entry is LessonEntry))
						continue;

					LessonEntry lesson = entry;
					if (lesson.course.current == exam.course) {
						var result = new LessonEntry(exam.start, exam.end);
						result.course = lesson.course;
						result.room = lesson.room;
						result.teacher = lesson.teacher;
						result.exam = exam;
						dur.entries.add(result);
						break;
					}
				}

				if (dur.entries.isNotEmpty)
					durations.add(dur);

				/* Exams being written at a time where the course does not have any
					 substitutions / regular lessons will not be shown in the timeline.
					 This might seem problematic, but I consider this to be a really rare
					 case not worth dealing with. They will still be shown in the exams
					 overview page.
				*/
			}
		}
	}

	void _fillRest(int days) {
		/*
		In order to find all sets of consecutive lesson-hours not interrupted, whe
		first take the current lesson-time as the starting point and increment that
		until there is a existing duration interrupting it. We can than save all
		hours between the starting time and the time before the interruption takes
		place as a phase of regular lessons.
		The check takes place before incrementing time in order to ensure that no
		duration that would be empty gets added (for instance when start is in an
		interrupting duration).
		 */

		var regularDurations = new List<_TimelineDuration>();
		var allHours = source.data.data.schoolHours;

		int regDays = 0;

		var time = new LessonTime.findForDate(new DateTime.now(), source.data.data.schoolHours);
		var start = new LessonTime.from(time);
		var lastYesterday = time;
		bool started = false;

		while (regDays < days) {
			bool foundInterruption = false;
			for (var dur in durations) {
				if (dur.type != _TimelineDuration.TYPE_INTERRUPTION)
					continue;

				if (dur.covers(time)) {
					//Skip to end of this interruption, there won't be any lessons until then
					time = dur.firstAfter(allHours);

					if (started) {
						started = false;
						regularDurations.add(new _TimelineDuration(_TimelineDuration.TYPE_REGULAR, start, dur.lastBefore(allHours)));
					}
					start = new LessonTime.from(time);

					foundInterruption = true;
					break;
				}
			}

			if (!foundInterruption) {
				started = true;
				//Move to next hour
				if (time.hour == allHours.last) {
					//Move to next day when no hours are left
					lastYesterday = time;
					time = new LessonTime(time.date.add(new Duration(days: 1)), allHours.first);
					regDays++;
				} else {
					time.hour = allHours[allHours.indexOf(time.hour) + 1];
				}
			}
		}

		//If there is an unsaved duration left, add that
		if (started) {
			regularDurations.add(new _TimelineDuration(_TimelineDuration.TYPE_REGULAR, start, lastYesterday));
		}

		durations.addAll(regularDurations);
		durations.sort();
	}

	void _finishAggregation() {
		for (var dur in durations) {
			if (dur.type == _TimelineDuration.TYPE_INTERRUPTION) {
				result.entries.addAll(dur.entries);
			} else if (dur.type == _TimelineDuration.TYPE_REGULAR) {
				result.entries.addAll(_findRegularLessons(dur));
			}
		}

		//Add date separators
		var allWeeks = source.data.data.weeks;

		LessonTime currentTime;
		List<TimelineEntry> entries = new List<TimelineEntry>();
		for (var entry in result.entries) {
			//Add a date separator when the date of the following entry changes
			if (entry.start.date != currentTime?.date) {
				currentTime = entry.start;
				entries.add(new DaySeparator(currentTime, Week.guessForDate(allWeeks, weeks, currentTime.date)));
			}

			entries.add(entry);
		}

		//Show a suggestion entry encouraging the user to set courses if not yet done
		var user = source.data.data.session.user;
		if (user.subscription.isEmpty && user.type == AccountType.STUDENT)
			entries.insert(0, new CourseSelectionSuggestion(null));

		//If turned on, create entries for free periods
		if (source.preferences.showFreePeriod) {
			_addFreePeriodMarkers(entries);
		}

		result.entries = entries;
	}

	void _addFreePeriodMarkers(List<TimelineEntry> entries) {
		bool breaksFreeTime(TimelineEntry entry) {
			if (entry is LessonEntry)
				return !entry.removed;
			if (entry is TimeInformationEntry) {
				return entry.entry.type.interruptsLesson();
			}

			return false;
		}

		//Iterate through all entries, keeping a reference to the last one. If there
		//some hours between two entries, insert a free period marker between them
		TimelineEntry current;

		var hours = source.data.data.schoolHours;
		var amountInserted = 0;

		var copy = new List<TimelineEntry>.from(entries);

		for (var i = 0; i < copy.length; i++) {
			var entry = copy[i];

			if (breaksFreeTime(entry)) {
				var old = current;
				current = entry;

				if (old == null)
					continue;

				//Add / subtract one hour so we only have the time not involved in this entry
				var endOfOld = old.end.nextTime(hours);
				var startOfCurrent = current.start.previousTime(hours);

				if (!endOfOld.isBefore(startOfCurrent, true)) //no hours in between
					continue;
				if (endOfOld.date != startOfCurrent.date
						|| old.end.date != current.start.date) { //different date, ignore
					old = null;
					continue;
				}

				entries.insert(i + (amountInserted++), new FreePeriodEntry(endOfOld, startOfCurrent));
			}
		}
	}

	List<TimelineEntry> _findRegularLessons(_TimelineDuration dur, {bool lessonsOnly: false}) {
		var lessons = new List<LessonEntry>();
		bool done = false;
		var consecutiveFails = 0;

		var allWeeks = source.data.data.weeks;
		var allLessons = source.data.data.lessons;
		var allHours = source.data.data.schoolHours;

		var current = dur.start;

		while (!done) {
			var week = Week.guessForDate(allWeeks, weeks, current.date);
			var dayOfWeek = current.date.weekday - 1;

			//Find lesson covering current
			var relLessons = allLessons.where((l) => l.day == dayOfWeek && l.weeks.contains(week) && l.coversHour(current.hour));
			if (relLessons.isNotEmpty) {
				consecutiveFails = 0;

				var lesson = relLessons.first;

				//Move start and end time so that this lesson fits into the parent duration
				var startTime = new LessonTime(current.date, lesson.start);
				bool fitsStart = dur.covers(startTime);
				if (!fitsStart) {
					startTime = dur.start;
				}
				var endTime = new LessonTime(current.date, lesson.end);
				if (!dur.covers(endTime)) {
					endTime = dur.end;
					done = true; //End of duration
					if (!fitsStart)
						break; //Lesson entirely out of duration
				}

				var timelineEntry = new LessonEntry.fromRegularLesson(startTime, endTime, lesson);
				lessons.add(timelineEntry);

				current = endTime.nextTime(allHours);
			} else {
				current = current.nextTime(allHours);

				if (current.isAfter(dur.end))
					done = true;

				if (++consecutiveFails > allHours.length * 7) {
					//For approx a week of regular days with no lessons, cancel searching
					done = true;
				}
			}
		}

		//Add time information
		if (!lessonsOnly) {
			/*
			Add time information entries at their correct location. We iterate through
			every lesson, keeping track of the previous one. For every lesson found,
			get a set of hours between the start of the first one and the end of the
			current lesson. Find all time entries between those hours and add them.
			 */

			var finishedLessons = new List<TimelineEntry>();

			var lastLesson;
			for (var lesson in lessons) {
				var currentLesson = lesson;

				var startTime = lastLesson?.start ?? dur.start;
				var endTime = currentLesson?.end;

				var hours = allHoursBetween(startTime, endTime, allHours, inclusive: true);
				var addLessonBeforeTimeEntry = false;
				
				for (var info in infoEntries) {
					if (info.included)
						continue;

					for (var hour in hours) {
						if (info.info.start.isBefore(hour, true) && info.info.end.isAfter(hour, true)) {
							//entry after the last lesson
							if (info.info.start.isBefore(lesson.end, false)) {
								finishedLessons.add(currentLesson);
								addLessonBeforeTimeEntry = true;
							}
							
							finishedLessons.add(new TimeInformationEntry(info.info));
							info.included = true;
							break;
						}
					}
				}

				if (!addLessonBeforeTimeEntry)
					finishedLessons.add(currentLesson);
				lastLesson = currentLesson;
			}

			return finishedLessons;
		} else {
			return new List<TimelineEntry>.from(lessons);
		}
	}
}