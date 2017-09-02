import 'dart:async';
import 'package:azuchath_flutter/logic/azuchath.dart';
import 'package:azuchath_flutter/logic/data/auth.dart';
import 'package:azuchath_flutter/logic/data/lessons.dart';
import 'package:azuchath_flutter/logic/data/timeinfo.dart';
import 'package:azuchath_flutter/logic/data/usercontent.dart';
import 'package:azuchath_flutter/logic/preferences.dart';
import 'package:azuchath_flutter/logic/timeline.dart';
import 'package:azuchath_flutter/ui/editor/manage_content.dart';
import 'package:azuchath_flutter/ui/settings/course_selection.dart';
import 'package:azuchath_flutter/ui/ui_utils.dart';
import 'package:azuchath_flutter/utils.dart';
import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';
import 'package:tuple/tuple.dart';

const TextStyle subjectText = const TextStyle(fontSize: 24.0);
const TextStyle infoText = const TextStyle(fontSize: 18.0);
const TextStyle infoTextChanged = const TextStyle(fontSize: 18.0, fontWeight: FontWeight.bold);

class _SuggestCourseSelectionWidget extends StatelessWidget {

	final VoidCallback setCourses;

	_SuggestCourseSelectionWidget(this.setCourses) : super(key: new UniqueKey());

  @override
  Widget build(BuildContext context) {
		return new Card(
			color: Colors.blue,
			child: new Container(
				padding: const EdgeInsets.all(16.0),
				child: new Column(
					children: [
						new Text("Klasse festlegen", style: Theme.of(context).textTheme.body2),
						const Text("Wir benötigen deine Klasse um zu wissen, welchen " +
								"Stundenplan wir dir anzeigen sollen. Bitte lege sie in den " +
								"Einstellungen fest."),
						new FlatButton(
							onPressed: setCourses,
							child: const Text("FESTLEGEN", style: const TextStyle(color: Colors.yellow)),
						)
					]
				)
			)
		);
  }
}

class _DaySeparatorWidget extends StatelessWidget {

	final String title;
	final Color color;

	static Color _getDayColor(int day) {
		switch (day) {
			case 0: return Colors.deepPurple;
			case 1: return Colors.green;
			case 2: return Colors.red;
			case 3: return Colors.yellow;
			case 4: return Colors.indigo;
			case 5: return Colors.lime;
			case 6: return Colors.orange;
			default: return Colors.blue;
		}
	}

	static _DaySeparatorWidget _buildForDate(DateTime date, Week week) {
		var day = getShortNameOfDay(date.weekday - 1);
		var formattedDate = humanFormatDate.format(date);

		return new _DaySeparatorWidget("$day. $formattedDate, ${week.name}", _getDayColor(date.weekday - 1));
	}

	/* Sometimes, the widget would be removed from the surrounding listview
	*  (just removed, you can't scroll there anymore) only when given a key.
	*  I could fix this by wrapping the widget in a Material widget.
	*  However, when switching to another page in the top-level scaffold body,
	*  it would be removed anyways.
	*  To conclude, this widget will not receive a key for now, as this seems to
	*  be the only way to circumvent this. That's an ugly workaround as this will
	*  reduce performance. */
	_DaySeparatorWidget(this.title, this.color) : super(key: null);

	@override
	Widget build(BuildContext context) {
		return new Center(
			child: new Container(
				margin: new EdgeInsets.symmetric(vertical: 8.0),
				child: new Column(
					children: [
						new Container(
							margin: const EdgeInsets.only(bottom: 4.0),
							width: 100.0,
							height: 4.0,
							color: color
						),
						new Text(
							title,
							style: new TextStyle(
								fontSize: 14.0,
								color: new Color.fromARGB(222, 0, 0, 0)
							)
						)
					]
				)
			)
		);
	}
}

class _FreePeriodWidget extends StatelessWidget {

	final LessonTime start;
	final LessonTime end;

	final Azuchath azu;

	_FreePeriodWidget(this.start, this.end, this.azu);

	String _createDescText() {
		var numStart = start.hour.number;
		var numEnd = end.hour.number;

		var descStart = numStart == numEnd ? "Freistunde" : "Freistunden";

		if (azu.preferences.timeMode == LessonTimeMode.EXACT_TIME) {
			var now = new DateTime.now(); //date doesn't matter, time provided by hour
			var startFormatted = humanFormatTime.format(start.hour.start.atDate(now));
			var endFormatted = humanFormatTime.format(end.hour.end.atDate(now));

			return "$descStart von $startFormatted bis $endFormatted";
		} else {
			if (numStart == numEnd) {
				return "$descStart in der $numStart. Stunde";
			} else {
				return "$descStart von der $numStart. bis zur $numEnd. Stunde";
			}
		}
	}

  @override
  Widget build(BuildContext context) {
  	return new Row(
			children: [
				new Container(
					margin: const EdgeInsets.symmetric(horizontal: 4.0),
				  child: new Icon(
				  	Icons.more_vert,
				  	color: Colors.black45,
				  ),
				),
				new Flexible(
					child: new Text(
						_createDescText(),
						style: new TextStyle(fontSize: 18.0, color: Colors.black54),
					)
				),
			]
		);
  }
}

enum _LessonWidgetType {
	NORMAL, CHANGED, REMOVED
}

typedef void _HWChangedCallback(bool completed, Homework hw);

class _LessonContent {
	LessonTime start;
	LessonTime end;

	_LessonWidgetType type;

	ChangedData<String> room;
	ChangedData<String> subject;

	String courseName;
	String form;

	String teacher;
	String message;

	List<Homework> hw;
}

class _LessonWidget extends StatelessWidget {

	final _LessonContent content;
	final bool firstInTimeline;
	final Azuchath azu;

	final _HWChangedCallback cb;

	final AnimationController hwExpandController;
	final ValueChanged<bool> hwExpandCb;
	final bool hwExpanded;

	static _LessonWidget _getForLesson(LessonEntry entry, _HWChangedCallback hwcb,
			bool hwExpanded, AnimationController hwExpandController,
			ValueChanged<bool> hwExpandCb, List<Homework> hw, bool firstInTl, Azuchath azu) {
		var content = new _LessonContent();

		content.start = entry.start;
		content.end = entry.end;

		content.type = entry.substitution ? (entry.removed ? _LessonWidgetType.REMOVED : _LessonWidgetType.CHANGED) : _LessonWidgetType.NORMAL;
		content.room = entry.room;
		//null course -> null, otherwise use subject name if available or course name
		content.subject = entry.course.map((c) => c == null ? null : c.subject ?? c.name);

		content.form = entry.course.current?.formName;
		content.courseName = entry.course.current?.name;

		if (entry.teacher != null)
			content.teacher = entry.teacher.fullName ?? entry.teacher.abbreviation;

		content.message = entry.message;

		content.hw = hw;

		return new _LessonWidget(content, firstInTl, hwcb, hwExpanded, hwExpandController, hwExpandCb, azu, new ObjectKey(entry));
	}

	_LessonWidget(this.content, this.firstInTimeline, this.cb, this.hwExpanded, this.hwExpandController, this.hwExpandCb, this.azu, Key key) : super(key: key);

	static Color _getCardColor(_LessonWidgetType type) {
		if (type == null)
			type = _LessonWidgetType.NORMAL;

		switch (type) {
			case _LessonWidgetType.NORMAL:
				return Colors.white;
			case _LessonWidgetType.CHANGED:
				return Colors.blue[600];
			case _LessonWidgetType.REMOVED:
				return Colors.red[400];
		}

		return Colors.white;
	}

	static String _getHeading(_LessonWidgetType type) {
		switch (type) {
			case _LessonWidgetType.CHANGED: return "Unterricht geändert";
			case _LessonWidgetType.REMOVED: return "Unterricht entfällt";
			default: return "Unterricht";
		}
	}

	Widget _buildInfo(BuildContext context, String hint, String content, [bool changed = false]) {
		return new Row(
				mainAxisSize: MainAxisSize.min,
				crossAxisAlignment: CrossAxisAlignment.baseline,
				textBaseline: TextBaseline.ideographic,
				children: [
					new Container(
							margin: new EdgeInsets.only(right: 4.0),
							child: new Text(hint, style: smallText(context))
					),
					new Text(content, style: changed ? infoTextChanged : infoText)
				]
		);
	}

	String _hourText(LessonHour h, {end:false}) {
		var time = end ? h.end : h.start;
		return humanFormatTime.format(time.atDate(new DateTime.now()));
	}

	///Shown on the top-left in an blue arrow when this lesson is next and
	///starting soon or about to be over
	Tuple2<String, bool> _startingAtText() {
		if (!firstInTimeline || content.type == _LessonWidgetType.REMOVED)
			return null;
		if (!azu.preferences.showNextTimeIndicator)
			return null;

		var now = new DateTime.now();
		now = new DateTime(now.year, now.month, now.day, now.hour, now.minute);

		var start = content.start.hour.start.atDate(content.start.date);
		var end = content.end.hour.end.atDate(content.start.date);

		bool useEndTime = false;
		var delta;

		if (now.isBefore(start)) {
			delta = start.difference(now);
		} else if (now.isBefore(end)) {
			useEndTime = true;
			delta = end.difference(now);
		} else {
			return null;
		}

		if (delta.inHours > 3)
			return null;

		var str;
		if (delta.inHours > 0) {
			var min = delta.inMinutes - delta.inHours * 60;

			str = "${delta.inHours} Std. $min min";
		} else if (delta.inMinutes > 0)
			str = "${delta.inMinutes} min";
		else
			return null;

		return new Tuple2(useEndTime ? "noch " + str : "in " + str, useEndTime);
	}

	void toggleHwExpand() {
		if (hwExpanded) {
			hwExpandController.reverse();
		} else {
			hwExpandController.forward();
		}

		hwExpandCb(!hwExpanded);
	}

	void onHwCompleteChanged(bool val, Homework hw) {
		cb(val, hw);
	}

	Widget buildHomework(BuildContext context) {
		var textStyleSmall = smallText(context);

		var unfinished = content.hw.where((hw) => !hw.completed);
		var canComplete = azu.data.data.session.user.type == AccountType.STUDENT;

		var topRow = new GestureDetector(
			onTap: toggleHwExpand,
			child: new Container(
				padding: const EdgeInsets.only(top: 8.0),
				child: new Row(
					mainAxisAlignment: MainAxisAlignment.spaceBetween,
					children: [
						new Row(
							children: [
								new Container(
									padding: const EdgeInsets.only(right: 8.0),
									child: new AnimatedCrossFade(
										crossFadeState:
										unfinished.isNotEmpty ? CrossFadeState.showFirst : CrossFadeState.showSecond,
										duration: const Duration(milliseconds: 200),
										firstChild: new Icon(Icons.assignment, color: Colors.red),
										secondChild: new Icon(Icons.done, color: Colors.green)
									),
								),
								canComplete ?
									new Text(unfinished.isNotEmpty ? "Noch Hausaufgaben" : "Alles fertig", style: textStyleSmall)
										: new Text("Hausaufgaben", style: textStyleSmall)
							]
						),

						new RotationTransition(
							turns: new MultAnimation(new CurvedAnimation(parent: hwExpandController, curve: Curves.linear), 0.5),
							child: new Icon(Icons.expand_more, size: 32.0)
						)
					]
				),
			)
		);

		var hwRows = new List<Row>();
		for (var hw in content.hw) {
			hwRows.add(new Row(
				mainAxisAlignment: MainAxisAlignment.spaceBetween,
				children: [
					new Expanded(
						child: new GestureDetector(
							onTap: () => onHwCompleteChanged(!hw.completed, hw),
							child: new Text(hw.content, style: textStyleSmall)
						)
					),
					new Container(
						width: 32.0,
						height: 32.0,
						child: canComplete ? new Checkbox(
							activeColor: Colors.green,
							value: hw.completed,
							onChanged: (complete) => onHwCompleteChanged(complete, hw)
						) : null
					)
				]
			));
		}

		return new Column(
			children: [
				topRow,
				new SizeTransition(
					sizeFactor: new CurvedAnimation(parent: hwExpandController, curve: Curves.easeInOut),
					axisAlignment: 0.0,
					child: new Column(
						children: hwRows
					),
				)
			]
		);
	}

	Widget _buildHour(LessonHour hour, BuildContext context, {end: false}) {
		if (azu.preferences.timeMode == LessonTimeMode.EXACT_TIME) {
			return new Text(_hourText(hour, end: end), style: smallText(context));
		} else {
			return new Text(hour.number.toString(), style: Theme.of(context).textTheme.body2);
		}
	}

	@override
	Widget build(BuildContext context) {
		var userAccountType = azu.data.data.session.user.type;
		var textStyleSmall = smallText(context);

		var infoRows = <Widget>[];
		//Don't show additional info (room & teacher) for removed lessons, would be
		//irrelevant
		if (content.type != _LessonWidgetType.REMOVED) {
			if (!content.room.bothNull())
				infoRows.add(_buildInfo(context, "in", content.room.current, content.room.hasChanged()));
			if (content.teacher != null && userAccountType != AccountType.TEACHER)
				infoRows.add(_buildInfo(context, "bei", content.teacher));
		}

		if (userAccountType == AccountType.TEACHER) {
			var formDesc = content.form ?? "mehrere";
			var courseDesc = content.courseName ?? "?";

			infoRows.add(_buildInfo(context, "mit", "$formDesc ($courseDesc)"));
		}

		var rows = <Widget>[
			new Row(
				crossAxisAlignment: CrossAxisAlignment.start,
				mainAxisAlignment: MainAxisAlignment.spaceBetween,
				children: [
					new Expanded(
						flex: 1,
						child: new Wrap(
							runSpacing: 8.0,
							children: [
								new Container(
									child: new Column(
										crossAxisAlignment: CrossAxisAlignment.start,
										children: [
											new Text(_getHeading(content.type), style: textStyleSmall),
											new Text(content.subject.current, style: subjectText)
										]
									),
									margin: const EdgeInsets.only(right: 12.0)
								),
								new Column(
									crossAxisAlignment: CrossAxisAlignment.start,
									children: infoRows,
								)
							]
						),
					),
					new Column(
						mainAxisAlignment: MainAxisAlignment.start,
						crossAxisAlignment: CrossAxisAlignment.end,
						children: [
							_buildHour(content.start.hour, context),
							_buildHour(content.end.hour, context, end: true),
						]
					),
				]
			)
		];

		if (content.message != null) {
			rows.add(new Row(
				children: [
					new Icon(Icons.info_outline),
					new Container(width: 8.0),
					new Text(content.message),
				]
			));
		}

		if (content.type != _LessonWidgetType.REMOVED && content.hw != null && content.hw.isNotEmpty) {
			rows.add(buildHomework(context));
		}

		var mainCard = new Card(
			child: new Container(
				padding: new EdgeInsets.all(16.0),
				color: _getCardColor(content.type),
				child: new Column(
					children: rows
				)
			)
		);

		var text = _startingAtText();
		if (text != null) {
			//Add an indicator to the top (overlapping the card) showing when the
			//lesson starts or finished.
			return new Stack(
				children: [
					new Container(
						margin: const EdgeInsets.only(top: 8.0),
						child: mainCard
					),
					new Positioned(
						left: 0.0,
						child: new CustomPaint(
							painter: new RightArrowPainter(text.item2 ? Colors.green : Colors.blue),
						  child: new Container(
						  	padding: const EdgeInsets.only(top: 4.0, left: 4.0, bottom: 4.0, right: 4.0 + RightArrowPainter.AR_SIZE),
						  	child: new Text(text.item1, style: const TextStyle(color: Colors.white)),
						  ),
						)
					)
				],
			);
		}

		return mainCard;
	}

}

class _InfoWidget extends StatelessWidget {

	final TimeInfo entry;

	_InfoWidget(this.entry) : super(key: new ObjectKey(entry.id));

	Color _getCardColor() {
		switch (entry.type) {
			case TimeInfoType.INFO: return Colors.lightBlue;
			case TimeInfoType.APPOINTMENT: return Colors.yellow;
			case TimeInfoType.HOLIDAY: return Colors.green;
			default: return Colors.red;
		}
	}

	String getTimeDescText() {
		var buff = new StringBuffer();
		if (entry.type.interruptsLesson())
			buff.write("Kein regulärer Unterricht ");
		else
			buff.write("Info ");

		if (entry.start.date == entry.end.date) { //Only a single day
			//am day, xx.xx.xx(, {von der x. Stunde}/{bis zur x. Stunde}/{in der x. Stunde}/{von der x. bis zur y. Stunde})
			buff.write("am ");
			buff.write(getNameOfDay(entry.start.date.weekday - 1));
			buff.write(", ");
			buff.write(humanFormatDateShort.format(entry.start.date));

			if (entry.start.hour == null && entry.end.hour == null) {
				//Entire day, no further description needed
			} else if (entry.start.hour == null || entry.end.hour == null) {
				//From start to x. hour or from x. hour to end?
				int hour;
				if (entry.start.hour == null) {
					buff.write(" bis zur ");
					hour = entry.end.hour.number;
				} else {
					buff.write(" ab der ");
					hour = entry.start.hour.number;
				}

				buff.write(hour);
				buff.write(". Stunde");
			} else {
				//Between two school hours on this day
				if (entry.start.hour == entry.end.hour) {
					buff.write(", in der ");
					buff.write(entry.start.hour.number);
					buff.write(". Stunde");
				} else {
					buff.write(", von der ");
					buff.write(entry.start.hour.number);
					buff.write(". bis zur ");
					buff.write(entry.end.hour.number);
					buff.write(". Stunde");
				}
			}
		} else {
			buff.write("ab ");
			_writeDay(buff, entry.start.hour, entry.start.date);
			buff.write(" bis ");
			_writeDay(buff, entry.end.hour, entry.end.date);
		}

		return buff.toString();
	}

	void _writeDay(StringBuffer buff, LessonHour hour, DateTime date) {
		buff.write(getNameOfDay(date.weekday - 1));
		buff.write(", ");
		buff.write(humanFormatDateShort.format(date));

		if (hour != null) {
			buff.write(", ");
			buff.write(hour.number);
			buff.write(". Stunde,");
		}
	}

	@override
	Widget build(BuildContext context) {
		var widgets = new List<Widget>();

		widgets.add(new Text(entry.name, style: subjectText, textAlign: TextAlign.center));
		if (entry.message != null)
			widgets.add(new Text(entry.message, style: infoText, textAlign: TextAlign.center));

		widgets.add(new Text(getTimeDescText(), textAlign: TextAlign.center));

		return new Card(
				child: new Container(
						padding: const EdgeInsets.all(16.0),
						color: _getCardColor(),
						child: new Column(
								children: widgets
						)
				)
		);
	}
}

class LessonTimeline extends StatefulWidget {

	final Azuchath azu;
	final VoidCallback refreshCb;

	LessonTimeline(this.azu, this.refreshCb, {Key key}) : super(key: key);

	@override
	State<StatefulWidget> createState() => new LessonsState(azu, refreshCb);
}

class LessonsState extends State<LessonTimeline> with TickerProviderStateMixin {

	Azuchath _azu;
	ScrollController _scroll = new ScrollController();
	bool canScrollEstimate = false;

	LessonsState(this._azu, this.refreshCb);

	Map<LessonEntry, bool> hwExpanded = new Map();
	Map<LessonEntry, AnimationController> controllers = new Map();

	bool noLessonsEasterEgg = false;
	int _firstLessonIndex;

	VoidCallback refreshCb;

	void _disposeAnim() {
		controllers.values.forEach((a) => a.dispose());
	}

	@override
	void dispose() {
		_disposeAnim();
		super.dispose();
	}

	@override
	Widget build(BuildContext context) {
		if (!_azu.timelineReady)
			return new Center(
				child: new Column(
					mainAxisAlignment: MainAxisAlignment.center,
					children: [
						new Container(
							padding: const EdgeInsets.only(bottom: 8.0),
							child: new Text(
								"Keine Daten verfügbar",
								textAlign: TextAlign.center,
								style: new TextStyle(
									fontSize: 32.0,
									fontWeight: FontWeight.bold,
									color: Colors.grey[500]
								),
							),
						),
						new Text(
							"Du kannst versuchen, eine Aktualisierung durchzuführen",
							textAlign: TextAlign.center,
							style: new TextStyle(
									fontSize: 16.0
							)
						),
						new RaisedButton(
							child: new Text("Aktualisieren", style: const TextStyle(color: Colors.blue)),
							onPressed: refreshCb
						)
					],
				)
			);

		for (var i = 0; i < _azu.timeline.entries.length; i++) {
			if (_azu.timeline.entries[i] is LessonEntry) {
				_firstLessonIndex = i;
				break;
			}
		}

		canScrollEstimate = _azu.timeline.entries.length > 5;

		return new ListView.builder(
			padding: const EdgeInsets.all(8.0),
			controller: _scroll,
			itemBuilder: _timelineBuilder,
			itemCount: _azu.timeline.entries.length,
		);
	}

	void markTimelineChanged() {
		hwExpanded.clear();
		_disposeAnim();
		controllers.clear();
	}

	Widget _buildTimelineEntry(int index, TimelineEntry entry) {
		if (entry is CourseSelectionSuggestion) {
			return new _SuggestCourseSelectionWidget(showCourseSelection);
		} else if (entry is DaySeparator) {
			return _DaySeparatorWidget._buildForDate(entry.start.date, entry.week);
		} else if (entry is LessonEntry) {
			var hw = _azu.timeline.findHomeworkForLesson(entry, _azu.data.data.homework);
			var expanded = hwExpanded.containsKey(entry) ? hwExpanded[entry] : false;

			var animationController = controllers.putIfAbsent(entry, () => new AnimationController(
					debugLabel: "HomeworkExpand::" + entry.hashCode.toString(),
					duration: const Duration(milliseconds: 500),
					vsync: this)
			);

			var lwdgt = _LessonWidget._getForLesson(entry, onHomeworkChanged, expanded, animationController, (e) => onHomeworkExpandedChange(entry, e), hw, index == _firstLessonIndex, _azu);
			if (noLessonsEasterEgg)
				lwdgt.content.type = _LessonWidgetType.REMOVED;
			return lwdgt;
		} else if (entry is TimeInformationEntry) {
			return new _InfoWidget(entry.entry);
		} else if (entry is FreePeriodEntry) {
			return new _FreePeriodWidget(entry.start, entry.end, _azu);
		}

		return new Text("????");
	}

	Widget _timelineBuilder(BuildContext ctx, int index) => _buildTimelineEntry(index, _azu.timeline.entries[index]);

	void onHomeworkExpandedChange(LessonEntry entry, bool expand) {
		setState(() => hwExpanded[entry] = expand);
	}

	void onHomeworkChanged(bool completed, Homework hw) {
		setState(() {
			hw.completed = completed;
			hw.completedSynced = false;
		});
		_azu.data.setHomeworkModified();
	}

	void showCourseSelection() {
		Navigator.of(context).push(
			new MaterialPageRoute<ContentNavResponse>(
				builder: (_) =>
				new CourseSelector(_azu, _azu.data.data.session.user.subscription)
			)
		);
	}

	Future<Null> scrollToTop() {
		if (canScrollEstimate)
		  return _scroll.animateTo(0.0, duration: new Duration(milliseconds: 700), curve: Curves.easeOut);
		return new Future.value(null);
	}
}