import 'package:azuchath_flutter/logic/azuchath.dart';
import 'package:azuchath_flutter/logic/data/auth.dart';
import 'package:azuchath_flutter/logic/data/lessons.dart';
import 'package:azuchath_flutter/logic/data/usercontent.dart';
import 'package:azuchath_flutter/ui/pages/timeline_lesson.dart';
import 'package:azuchath_flutter/ui/ui_core.dart';
import 'package:azuchath_flutter/ui/ui_utils.dart';
import 'package:azuchath_flutter/utils.dart';
import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';

class ExamsOverview extends StatefulWidget {

	final Azuchath _azuchath;

  ExamsOverview(this._azuchath);

  @override
  State<StatefulWidget> createState() => new _ExamsOverviewState();
}

class _ExamsOverviewState extends State<ExamsOverview> {

	List<Exam> get examsFuture {
		var data = widget._azuchath.data.data;

		var all = data.exams;
		var now = new LessonTime.findForDate(new DateTime.now(), data.schoolHours);

		return all.where((ex) => ex.end.isAfter(now, true)).toList();
	}

  @override
  Widget build(BuildContext context) {
		var exams = this.examsFuture;

  	if (exams.isEmpty) {
  		var mainColor = Colors.black38;
  		var highlightColor = Colors.black54;

  		return new Center(
			  child: new Column(
			  	mainAxisSize: MainAxisSize.max,
			  	mainAxisAlignment: MainAxisAlignment.center,
			  	children: [
			  		new Icon(Icons.mode_edit, size: 50.0, color: mainColor,),
						new Text(
							"Keine Klausuren",
							textAlign: TextAlign.center,
							style: Theme.of(context).textTheme.display1.copyWith(color: highlightColor),
						),
						new Text(
							"Der Klausurenplaner wird schrittweise für alle Klassen eingeführt. "
							"Bitte habe noch einen Moment Geduld.",
							textAlign: TextAlign.center, style: new TextStyle(color: mainColor),
						),
			  	],
			  ),
			);
		}

		bool isTeacher = widget._azuchath.data.data.session.user.type == AccountType.TEACHER;

  	return new ListView.builder(
			primary: true,
			itemBuilder: (context, i) =>
				new ExamCard(exams[i], showForTeacher: isTeacher),
			itemCount: exams.length,
		);
	}
}

class ExamCard extends StatelessWidget {

	final Exam exam;
	final bool showForTeacher;

	ExamCard(this.exam, {this.showForTeacher = false});

	Widget _topRow() {
		var content = <Widget>[];

		var learningProgress = exam.calcLearningProgress();
		var percentageLearned = (learningProgress * 100).round();
		var hardlyLearned = Colors.red;
		var wellLearned = Colors.green;

		if (!showForTeacher) {
			content.add(
				new Text(
					"$percentageLearned% gelernt",
					style: new TextStyle(
						color: new ColorTween(begin: hardlyLearned, end: wellLearned).lerp(learningProgress)
					)
				)
			);
		} else {
			content.add(new Container()); //just needed for layout, second child right
		}

		content.add(new Text(humanFormatDateShort.format(exam.start.date)));
		
		return new Row(
			mainAxisAlignment: MainAxisAlignment.spaceBetween,
			children: content,
		);
	}
	
	Widget _courseRow(BuildContext context) {
		var content = <Widget>[];
		
		content.add(new Text(exam.course.displayName, style: subjectText));

		if (showForTeacher) {
			content.add(
				new Container(
					margin: const EdgeInsets.only(left: 4.0),
					child: LessonWidget.buildInfo(context, "mit", exam.course.formName ?? "mehreren")
				)
			);
		}

		return new Row(
			crossAxisAlignment: CrossAxisAlignment.baseline,
			textBaseline: TextBaseline.ideographic,
			children: content,
		);
	}
	
  @override
  Widget build(BuildContext context) {
		String topicsDesc;
		if (exam.topics.length == 1) {
			topicsDesc = "Klausur mit einem Thema";
		} else if (exam.topics.length > 1) {
			topicsDesc = "Klausur mit ${exam.topics.length} Themen";
		} else {
			topicsDesc = "Keine Themen hinterlegt";
		}

  	return new Card(
			child: new Container(
				padding: const EdgeInsets.all(8.0),
			  child: new Column(
			  	crossAxisAlignment: CrossAxisAlignment.start,
			  	children: [
			  		new Container(
							padding: const EdgeInsets.only(left: 8.0, top: 8.0, right: 8.0),
						  child: new Column(
								crossAxisAlignment: CrossAxisAlignment.start,
						  	children: [
						  		_topRow(),
									_courseRow(context),
									LessonWidget.buildInfo(context, "über", exam.title, false, exam.heroTitle),
						  	],
						  ),
						),
			  		new Divider(),
						new Row(
							mainAxisAlignment: MainAxisAlignment.spaceBetween,
							children: [
								new FlatButton(
									onPressed: () => HUSScaffold.of(context).showExamDetails(exam),
									child: const Text(
										"DETAILS",
										style: const TextStyle(color: Colors.lightBlue)
									)
								),
								new Container(
									margin: const EdgeInsets.only(right: 8.0),
									child: new Text(topicsDesc, style: smallText(context))
								),
							],
						),
			  	]
			  ),
			),
		);
  }
}

class ExamDetailScreen extends StatefulWidget {

	final Azuchath azuchath;
	final Exam exam;

	ExamDetailScreen(this.azuchath, this.exam);

  @override
  State<StatefulWidget> createState() => new _ExamDetailState();
}

class _ExamDetailState extends State<ExamDetailScreen> {

	Widget buildGeneralInfo() {
		var exam = widget.exam;

		var dateStr = "${humanFormatDate.format(exam.start.date)}, ${exam.start.hour.number}. - ${exam.end.hour.number}. Stunde";

		return new Column(
			crossAxisAlignment: CrossAxisAlignment.start,
			children: [
				new Row(
					mainAxisSize: MainAxisSize.max,
				  children: <Widget>[
				    new Expanded(
				      child: new Hero(
				      	tag: exam.heroTitle,
				      	child:
				      		new Text(
				      			exam.title,
				      			style: mediumText(context)
				      					.copyWith(color: Colors.black, fontSize: 22.0)
				      		)
				      ),
				    ),
				  ],
				),
				new Container(height: 8.0),
				new Container(
					margin: const EdgeInsets.only(left: 8.0),
					child: LessonWidget.buildInfo(context, "in", exam.course.displayName)
				),
				new Container(
					margin: const EdgeInsets.only(left: 8.0),
					child: LessonWidget.buildInfo(context, "am", dateStr)
				),
			],
		);
	}

	TableRow buildTopicRow(ExamTopic topic) {
		var rows = <Text>[
			new Text(topic.content, style: const TextStyle(fontSize: 16.0)),
		];
		if (topic.explanation != null) {
			rows.add(new Text(topic.explanation, style: smallText(context)));
		}

		return new TableRow(
			children: [
				new Column(
					crossAxisAlignment: CrossAxisAlignment.start,
					children: rows
				),
				buildLearningButtons(topic)
			]
		);
	}

	void changeLearningStatus(ExamTopic topic, ExamLearningStatus updated) {
		setState(() {
			topic.learned = updated;
			topic.learningChanged = true;
			widget.azuchath.data.setExamsModified();
		});
	}

	Widget buildLearningIcon(ExamTopic topic, ExamLearningStatus status) {
		var selected = topic.learned == status;

		IconData icon;
		Color activeColor;
		switch (status) {
			case ExamLearningStatus.POOR:
				icon = Icons.sentiment_dissatisfied;
				activeColor = Colors.red;
				break;
			case ExamLearningStatus.MODERATE:
				icon = Icons.sentiment_neutral;
				activeColor = Colors.yellow;
				break;
			case ExamLearningStatus.WELL:
				icon = Icons.sentiment_satisfied;
				activeColor = Colors.green;
				break;
		}

		return new Material(
			color: selected ? Colors.white70 : Colors.transparent,
			type: MaterialType.circle,
		  child: new InkWell(
				onTap: () => changeLearningStatus(topic, status),
		    child: new Icon(
		    	icon,
		    	color: selected ? activeColor : Colors.black45, size: 36.0
		    ),
		  ),
		);
	}
	
	Widget buildLearningButtons(ExamTopic topic) {
		return new Row(
			mainAxisSize: MainAxisSize.max,
			children: [
				buildLearningIcon(topic, ExamLearningStatus.POOR),
				buildLearningIcon(topic, ExamLearningStatus.MODERATE),
				buildLearningIcon(topic, ExamLearningStatus.WELL),
			],
		);
	}

  @override
  Widget build(BuildContext context) {
		var mainContent = <Widget>[
			buildGeneralInfo(),
			new Divider()
		];

		if (widget.exam.topics.isNotEmpty) {
			var rows = [
				new TableRow(
					children: [
						new Container( //to define height of the whole table row
							margin: const EdgeInsets.symmetric(vertical: 8.0),
							child: new Text("Thema", style: smallText(context))
						),
						new Text(
							"gelernt?",
							style: smallText(context),
							textAlign: TextAlign.end
						)
					]
				)
			];

			for (var topic in widget.exam.topics) {
				rows.add(buildTopicRow(topic));
			}

			mainContent.add(
				new Table(
					columnWidths: {0: null, 1: new IntrinsicColumnWidth()},
					defaultVerticalAlignment: TableCellVerticalAlignment.middle,
					children: rows,
				)
			);
		} else {
			mainContent.add(
				new Center(
					child: new Text("Keine Themen verfügbar", style: mediumText(context)),
				)
			);
		}

  	return new HUSScaffold(
			widget.azuchath,
			title: "Klausurthemen",
			content: new ListView(
				padding: const EdgeInsets.all(8.0),
			  children: mainContent,
			)
		);
  }
}