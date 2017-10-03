import 'dart:async';
import 'package:azuchath_flutter/logic/azuchath.dart';
import 'package:azuchath_flutter/logic/data/auth.dart';
import 'package:azuchath_flutter/logic/data/lessons.dart';
import 'package:azuchath_flutter/logic/data/usercontent.dart';
import 'package:azuchath_flutter/ui/editor/manage_content.dart';
import 'package:azuchath_flutter/ui/ui_utils.dart';
import 'package:azuchath_flutter/ui/dialogs.dart' as dialogs;
import 'package:azuchath_flutter/utils.dart';
import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';

enum _HWValidationStatus {
	ERROR_NO_COURSE, ERROR_NO_TIME, ERROR_EMPTY_CONTENT, ERROR_TIME, SUCCESS
}

class HomeworkEditor {

	Homework _source;
	Homework _fake;
	bool isNew = false;

	bool get subjectSelected => _fake.course != null;

	Course get course => _fake.course;
	set course(Course c) => _fake.course = c;

	DateTime get due => _fake.due;
	set due(DateTime date) => _fake.due = LessonTime.normDate(date);

	bool get publish => _fake.published;
	set publish(bool p) => _fake.published = p;

	String get content => _fake.content;
	set content(String c) => _fake.content = c;

	int get timeMin => _fake.timeMin;
	set timeMin(int i) => _fake.timeMin = i;
	int get timeMax => _fake.timeMax;
	set timeMax(int i) => _fake.timeMax = i;

	bool canEditCourse() => _source == null;
	bool canEditPublishStatus() => _source == null || !_source.published;

	_HWValidationStatus get validationStatus {
		if (!subjectSelected)
			return _HWValidationStatus.ERROR_NO_COURSE;
		if (due == null)
			return _HWValidationStatus.ERROR_NO_TIME;
		if (content == null || content.trim().isEmpty)
			return _HWValidationStatus.ERROR_EMPTY_CONTENT;

		if (timeMin > timeMax)
			return _HWValidationStatus.ERROR_TIME;
		if (timeMax > 120)
			return _HWValidationStatus.ERROR_TIME;

		return _HWValidationStatus.SUCCESS;
	}

	HomeworkEditor.createNewHomework(PublicUserInfo creator) {
		_fake = new Homework(-1, creator, null, null, null, true, false);
		due = new DateTime.now();
		isNew = true;
		timeMin = 10;
		timeMax = 20;
	}

	HomeworkEditor.of(Homework hw) {
		_fake = new Homework(hw.id, hw.creator, hw.course, hw.due, hw.content, hw.published, hw.completed);
		_source = hw;

		if (hw.timeMin == 0)
			timeMin = 10;
		else
			timeMin = hw.timeMin;
		if (hw.timeMax == 0)
			timeMax = 20;
		else
			timeMax = hw.timeMax;
	}

	Homework applyAndFinish() {
		if (isNew) {
			_source = _fake; //Needed for hero transitions
			return _fake;
		} else {
			//These are the only fields that can be changed after creating the homework
			_source.due = _fake.due;
			_source.content = _fake.content;
			_source.published = _fake.published;
			_source.timeMin = _fake.timeMin;
			_source.timeMax = _fake.timeMax;

			return _source;
		}
	}
}

class EditHomework extends StatefulWidget {

	final Azuchath azu;
	final HomeworkEditor editor;

	final VoidCallback onFinishedChanged;

	EditHomework(this.azu, this.editor, this.onFinishedChanged, {Key key}) : super(key: key);

  @override
  State<StatefulWidget> createState() => new HomeworkEditState(azu, editor, onFinishedChanged);
}

class HomeworkEditState extends ContentManager<EditHomework> {

	Azuchath azu;
	HomeworkEditor editor;

	List<DateTime> knownLessonDates;

	bool canFinish;
	_HWValidationStatus currentStatus;
	VoidCallback onFinishedChanged;

	TextEditingController contentController;
	TextEditingController timeMinController;
	TextEditingController timeMaxController;

	bool dateManuallySelected = false;

	HomeworkEditState(this.azu, this.editor, this.onFinishedChanged) {
		if (editor.course != null)
			_setCourse(editor.course); //Load knownLessonDates

		contentController = new TextEditingController(text: editor.content);
		contentController.addListener(onContentChanged);

		timeMinController = new TextEditingController(text: editor.timeMin.toString());
		timeMinController.addListener(onTimeChanged);

		timeMaxController = new TextEditingController(text: editor.timeMax.toString());
		timeMaxController.addListener(onTimeChanged);

		currentStatus = editor.validationStatus;
	}

	@override
	void setState(VoidCallback fn) {
		fn();

		currentStatus = editor.validationStatus;
		bool canFinishNow = currentStatus == _HWValidationStatus.SUCCESS;
		if (canFinish != canFinishNow) {
			canFinish = canFinishNow;
			onFinishedChanged();
		}

		super.setState(() => {});
	}

	bool _lessonOnDate(DateTime date, {DateTime alsoOk}) {
		if (date == alsoOk)
			return true;
		return knownLessonDates != null && knownLessonDates.contains(LessonTime.normDate(date));
	}

	void _setCourse(Course course) {
		editor.course = course;
		var lessons = azu.timeline.findLessonsForCourse(editor.course);
		knownLessonDates = lessons.map((l) => l.start.date).toList();

		//If the date has not yet been selected manually, preselect the next lesson
		//as the date for the homework.
		var now = LessonTime.normDate(new DateTime.now());
		if (!dateManuallySelected) {
			for (var date in knownLessonDates) {
				if (date.isAfter(now)) {
					editor.due = date;
					break;
				}
			}
		}
	}

	Future<Null> showSubjectSelection(BuildContext context) async {
		var user = azu.data.data.session.user;
		var course = await dialogs.showCourseDialog(context,
				user.subscription, user.type == AccountType.TEACHER);
		if (course != null)
			setState(() => _setCourse(course));
	}

	Future<Null> showDateSelection(BuildContext context) async {
		var currentDate = editor.due;
		var lastDate = azu.timeline.entries.last.start.date;

		var date = await showDatePicker(context: context,
				firstDate: LessonTime.normDate(new DateTime.now()),
				lastDate: lastDate,
				initialDate: currentDate,
				selectableDayPredicate: (d) => _lessonOnDate(d, alsoOk: currentDate));
		if (date != null) {
			dateManuallySelected = true;
			setState(() => editor.due = date);
		}
	}

	void onPublishedChanged(bool val) {
		setState(() => editor.publish = val);
	}

	void onContentChanged() {
		setState(() => editor.content = contentController.text);
	}

	void onTimeChanged() {
		setState(() {
			editor.timeMin = timeMinController.text.isEmpty ? 0 :
				int.parse(timeMinController.text);
			editor.timeMax = timeMaxController.text.isEmpty ? 0 :
			int.parse(timeMaxController.text);
		});
	}

	String _formatDate(DateTime date) {
		var day = getShortNameOfDay(date.weekday - 1);
		var formattedDate = humanFormatDateShort.format(date);

		return "$day., $formattedDate";
	}

  @override
  Widget build(BuildContext context) {
		Widget courseText = new Text(
				editor.subjectSelected ? editor.course.displayName : "",
				style: Theme.of(context).textTheme.headline);
		if (editor._source?.heroCourse != null) {
			courseText = new Hero(
				tag: editor._source.heroCourse,
				child: courseText
			);
		}

		var subjectEntries = <Widget>[
			new Column(
					crossAxisAlignment: CrossAxisAlignment.start,
					children: [
						new Text(editor.subjectSelected
								? "Fach ausgewählt:"
								: "Kein Fach ausgewählt", style: smallText(context)),
						new Container(
							margin: const EdgeInsets.only(left: 8.0, top: 8.0),
							child: courseText
						),
					]
			)
		];

		if (editor.canEditCourse()) {
			subjectEntries.add(new FlatButton(
				child: new Text(
					editor.subjectSelected ? "ÄNDERN" : "AUSWÄHLEN",
					style: new TextStyle(
						color: editor.subjectSelected ? Colors.orange :
						Colors.green,
					)
				),
				onPressed: () => showSubjectSelection(context)
			));
		}

		var editSubject = new Row(
			mainAxisAlignment: MainAxisAlignment.spaceBetween,
			children: subjectEntries
		);

		var editDate = new Container(
			margin: const EdgeInsets.only(top: 16.0),
			child: new Row(
				mainAxisAlignment: MainAxisAlignment.spaceBetween,
				children: [
					new Column(
						crossAxisAlignment: CrossAxisAlignment.start,
						children: [
							new Text("Datum", style: smallText(context)),
							new Container(
								margin: const EdgeInsets.only(left: 8.0, top: 8.0),
								child: new Text(
									_formatDate(editor.due), style: Theme.of(context).textTheme.headline)
							)
						]
					),
					new FlatButton(
						child: new Text(
							"ÄNDERN", style: new TextStyle(color: Colors.indigo)
						),
						onPressed: () => showDateSelection(context)
					)
				]
			)
		);

		var entries = [editSubject, editDate];
		if (!_lessonOnDate(editor.due))
			entries.add(new Text(
					"Wird aufgrund des Datums ggf. nicht in Timeline angezeigt",
					style: smallText(context).copyWith(color: Colors.deepOrange)));

		var editPublishing = new Container(
				margin: const EdgeInsets.only(top: 8.0),
				child: new CheckboxListTile(
						dense: true,
						title: const Text("Auch für Mitschüler veröffentlichen"),
						controlAffinity: ListTileControlAffinity.leading,
						onChanged: editor.canEditPublishStatus() ? onPublishedChanged : null,
						value: editor.publish
				)
		);
		entries.add(editPublishing);

		Widget textInput = new TextField(
			controller: contentController,
			maxLines: 5, //TODO Change back to null after https://github.com/flutter/flutter/issues/11582 gets fixed
			style: mediumText(context).copyWith(color: Colors.black),
			decoration: new InputDecoration(
				hintText: "Inhalt der Hausaufgabe hier eingeben",
			),
		);

		entries.add(textInput);

		//Input fields to suggest the time it will take to complete this homework
		entries.add(new Row(
			mainAxisSize: MainAxisSize.min,
			children: [
				new Container(
					child: const Text("Dauer:"),
					margin: const EdgeInsets.only(right: 4.0)
				),
				new Flexible(
				  child: new TextField(
						controller: timeMinController,
				  	keyboardType: TextInputType.number,
				  	maxLines: 1,
				  	decoration: new InputDecoration(
							hintText: "5"
				  	),
				  ),
				),
				new Container(
					child: const Text("bis"),
					margin: const EdgeInsets.symmetric(horizontal: 4.0),
				),
				new Flexible(
				  child: new TextField(
						controller: timeMaxController,
				  	keyboardType: TextInputType.number,
				  	maxLines: 1,
				  	decoration: new InputDecoration(
							hintText: "10"
				  	),
				  ),
				),
				new Container(
					child: const Text("Minuten"),
					margin: const EdgeInsets.only(left: 4.0)
				),
			],
		));

		if (currentStatus != _HWValidationStatus.SUCCESS) {
			String errorMsg = "";

			switch (currentStatus) {
				case _HWValidationStatus.ERROR_NO_COURSE:
					errorMsg = "Bitte wähle zuerst das Fach!";
					break;
				case _HWValidationStatus.ERROR_NO_TIME:
					errorMsg = "Bitte gib ein gültiges Datum ein!";
					break;
				case _HWValidationStatus.ERROR_EMPTY_CONTENT:
					errorMsg = "Bitte lege den Inhalt der Hausaufgabe fest!";
					break;
				case _HWValidationStatus.ERROR_TIME:
					errorMsg = "Die Zeit ist ungültig: Sie darf nicht mehr als zwei "
						"Stunden betragen und das Minimum sollte kleiner als sein als das "
						"Maximum";
					break;
				default:
					break;
			}

			entries.add(
				new Text(
					errorMsg, style: smallText(context).copyWith(color: Colors.red)
				)
			);
		}

		return new SingleChildScrollView(
				child: new Container(
						margin: new EdgeInsets.all(16.0),
						child: new Column(
								crossAxisAlignment: CrossAxisAlignment.start,
								children: entries
						)
				)
		);
	}

  @override
  bool canBeCompleted() => editor.validationStatus == _HWValidationStatus.SUCCESS;

  @override
  Future complete() async {
  	if (editor.isNew) {
  		var hw = editor.applyAndFinish();

			hw.syncStatus = HomeworkSyncStatus.CREATED;
			hw.completedSynced = true;

			azu.data.data.homework.add(hw);
		} else {
  		var hw = editor.applyAndFinish();
  		hw.syncStatus = HomeworkSyncStatus.EDITED;
		}

		azu.data.setHomeworkModified();
  }
}