import 'dart:async';
import 'package:azuchath_flutter/logic/data/lessons.dart';
import 'package:azuchath_flutter/ui/ui_utils.dart';
import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';

class CourseSelection extends StatelessWidget {

	final List<Course> available;
	final bool showAsTeacher;

	CourseSelection(this.available, this.showAsTeacher);

	void selectCourse(Course c, BuildContext ctx) {
		Navigator.of(ctx).pop(c);
	}

	String _getCourseDetailName(Course course) {
		if (!showAsTeacher) {
			return course.name;
		} else {
			return "${course.name} / ${course.formName ?? "mehrere"}";
		}
	}

  @override
  Widget build(BuildContext context) {
  	var children = <Widget>[
			new Container(
				margin: const EdgeInsets.symmetric(vertical: 8.0),
				child: new Text("Fach auswählen", style: Theme.of(context).textTheme.headline)
			)
		];

		for (var course in available) {
			children.add(
				new FlatButton(
					child: new Container(
						margin: const EdgeInsets.all(4.0),
						child: new Row(
							crossAxisAlignment: CrossAxisAlignment.end,
							children: [
								new Container(
									margin: const EdgeInsets.only(right: 4.0),
									child: new Text(course.displayName, style: mediumText(context))
								),
								new Text(_getCourseDetailName(course), style: smallText(context))
							]
						)
						),
						onPressed: () => selectCourse(course, context),
				)

			);
		}

		return new Dialog(
			child: new SingleChildScrollView(
				child: new Column(
					children: children,
				)
			)
		);
  }
}

Future<Course> showCourseDialog(BuildContext ctx, List<Course> courses, bool showAsTeacher) {
	return showDialog(context: ctx, child: new CourseSelection(courses, showAsTeacher));
}