import 'dart:async';
import 'package:azuchath_flutter/logic/azuchath.dart';
import 'package:azuchath_flutter/logic/data/auth.dart' as data;
import 'package:azuchath_flutter/logic/data/lessons.dart';
import 'package:azuchath_flutter/ui/ui_utils.dart';
import 'package:flutter/material.dart';

enum _CourseSelectionStep {
	FETCHING_FORMS, DISPLAYING_FORMS, FETCHING_COURSES, DISPLAYING_COURSES, SUBMITTING
}

class _CourseGroup {

	String title;
	List<Teacher> duplicateTeachers;

	List<Course> entries;
	bool supportsMulti;

	_CourseGroup(this.title, this.duplicateTeachers, this.entries, this.supportsMulti);

	Course findSelected(_CourseSelectionData s) {
		for (var c in entries) {
			if (s.visibleSelected.contains(c))
				return c;
		}

		return s.currentGroupIndex < s.maxGroupIndex || s.currentlyNoSelected ? s.noCourse : null;
	}

	static List<Teacher> _findDuplicates(List<Course> courses) {
		List<Teacher> handled = [];
		List<Teacher> duplicates = [];

		for (var c in courses) {
			var t = c.teacher;
			if (handled.contains(t))
				duplicates.add(t);
			else
				handled.add(t);
		}

		return duplicates;
	}

	static List<_CourseGroup> inGroups(List<Course> courses) {
		var groups = new Map<String, _CourseGroup>();

		_CourseGroup additionalGroup = new _CourseGroup("Zusatzfächer", [], [], true);

		for (var course in courses) {
			var subjectName = course.subject;
			if (subjectName == null) {
				additionalGroup.entries.add(course);
			} else {
				var group = groups.putIfAbsent(subjectName,
								() => new _CourseGroup(subjectName, [], [], false));

				group.entries.add(course);
			}
		}

		for (var group in groups.values) {
			group.entries.sort((a, b) => a.name.compareTo(b.name));

			group.duplicateTeachers = _findDuplicates(group.entries);
		}

		return new List<_CourseGroup>.from(groups.values)..add(additionalGroup);
	}

}

class _CourseSelectionData {

	final Course noCourse = new Course(0, null, null, null);

	_CourseSelectionStep step;

	List<data.Form> allForms;
	data.Form selectedForm;

	List<Course> allCourses;
	List<_CourseGroup> groups;
	int currentGroupIndex = 0;
	int maxGroupIndex = 0;
	bool currentlyNoSelected = false;

	List<Course> previouslySelected = new List<Course>();
	List<Course> selected = new List<Course>();

	Set<Course> get visibleSelected {
		var set = new Set<Course>.from(previouslySelected);
		set.addAll(selected);
		return set;
	}

	String error;

	set form (data.Form selected) {
		selectedForm = selected;

		allCourses = null;
		groups = null;
	}

	bool get isError => error != null;

	_CourseSelectionData() {
		step = _CourseSelectionStep.FETCHING_FORMS;
	}

	Future loadAllForms(Azuchath azu) async {
		if (allForms != null)
			return;

		try {
			var res = await azu.api.getAllForms();
			if (res.success) {
				allForms = res.forms;
				step = _CourseSelectionStep.DISPLAYING_FORMS;
			} else {
				error = "Die Klassen konnten nicht von unserem Server abgerufen werden";
			}
		} catch (e) {
			print(e);
			error = "Die Klassen konnten nicht von unserem Server abgerufen werden";
		}
	}

	Future loadCourses(Azuchath azu) async {
		if (allCourses != null)
			return;

		try {
			var res = await azu.api.getCoursesInForm(selectedForm, azu.data.data);
			if (res.success) {
				allCourses = res.courses;
				groups = _CourseGroup.inGroups(allCourses);
				step = _CourseSelectionStep.DISPLAYING_COURSES;
			} else {
				error = "Die Kurse konnten nicht von unserem Server abgerufen werden";
			}
		} catch (e) {
			error = "Die Kurse konnten nicht von unserem Server abgerufen werden";
		}
	}

	Future submitSubscription(Azuchath azu) async {
		var start = new DateTime.now();

		var data = azu.data.data;

		try {
			var res = await azu.api.setSubscription(selectedForm, selected);
			if (res.success)
				data.session.user.subscription = new List<Course>.from(res.subscription.map((c) => data.handleCourse(c)));
			azu.data.markDirty();
			//Start sync, but don't wait for it
			azu.syncWithServer();
		} catch (e) {
			print(e);
			error = "Die Kurse konnten nicht gespeichert werden";
		}

		//Display the loading screen a bit longer
		if (new DateTime.now().difference(start).inMilliseconds < 500)
			await new Future.delayed(new Duration(milliseconds: 500));
	}
}

class CourseSelector extends StatefulWidget {

	final List<Course> existingSubscription;
	final Azuchath azu;

	CourseSelector([this.azu, this.existingSubscription]);

  @override
  State<StatefulWidget> createState() => new CourseSelectionState(azu, existingSubscription);
}

class CourseSelectionState extends State<CourseSelector> {

	_CourseSelectionData selector;

	final List<Course> existingSubscription;
	final Azuchath azu;

	CourseSelectionState([this.azu, this.existingSubscription]);

	void init() {
		selector = new _CourseSelectionData();

		if (existingSubscription != null && existingSubscription.isNotEmpty) {
			selector.previouslySelected = existingSubscription;
		}

		handleStepChanged();
	}

	void handleStepChanged() {
		if (selector.step == _CourseSelectionStep.FETCHING_FORMS) {
			if (selector.error == null) {
				selector.loadAllForms(azu).then((_) => handleStepChanged());
			}
		} else if (selector.step == _CourseSelectionStep.FETCHING_COURSES) {
			if (selector.error == null) {
				selector.loadCourses(azu).then((_) {
					if (selector.selected != null && selector.selected.isNotEmpty) {
						selector.maxGroupIndex = selector.groups.length - 1;
					}
				  handleStepChanged();
				});
			}
		} else if (selector.step == _CourseSelectionStep.SUBMITTING) {
			if (selector.error == null) {
				selector.submitSubscription(azu).then((_) => Navigator.pop(context));
			}
		}

		setState(() {});
	}

	Future onFormSelected(data.Form form) async {
		selector.form = form;
		setState(() {});
		await new Future.delayed(new Duration(milliseconds: 500));
		selector.step = _CourseSelectionStep.FETCHING_COURSES;
		handleStepChanged();
	}

	Future onCourseSelected(Course course, _CourseGroup group) async {
		//Remove course that could have been selected earlier
		selector.selected.remove(group.findSelected(selector));
		if (course != selector.noCourse) {
			selector.selected.add(course);
		} else {
			selector.currentlyNoSelected = true;
		}

		setState(() {}); //To show the radio button becoming selected
		await new Future.delayed(new Duration(milliseconds: 500));
		selector.currentlyNoSelected = false;

		nextStep();
	}

	void onCourseMultiSelected(Course course, bool selected) {
		if (selected) {
			selector.selected.add(course);
		} else {
			selector.selected.remove(course);
		}

		setState(() {});
	}

	void nextStep() {
		selector.currentGroupIndex++;
		if (selector.currentGroupIndex > selector.maxGroupIndex)
			selector.maxGroupIndex = selector.currentGroupIndex;

		if (selector.currentGroupIndex >= selector.groups.length) {
			selector.step = _CourseSelectionStep.SUBMITTING;
		}

		handleStepChanged();
	}

	void previousStep() {
		if (selector.currentGroupIndex > 0)
			selector.currentGroupIndex--;

		handleStepChanged();
	}

	Widget _showLoading(String desc, BuildContext context) {
		return new Center(
		  child: new Column(
		  	mainAxisAlignment: MainAxisAlignment.center,
		  	crossAxisAlignment: CrossAxisAlignment.center,
		  	children: [
		  		new Container(
						margin: const EdgeInsets.only(bottom: 8.0),
		  		  child: new CircularProgressIndicator(
		  		  	valueColor: new AlwaysStoppedAnimation(Theme.of(context).primaryColor),
		  		  ),
		  		),
		  		new Text(desc, style: mediumText(context).copyWith(color: Colors.blueAccent))
		  	]
		  ),
		);
	}

	Widget _showError(String desc, BuildContext context) {
		return new Padding(
			padding: const EdgeInsets.all(16.0),
		  child: new Column(
		  	children: [
		  		new Text("Ein Fehler ist aufgetreten", style: Theme.of(context).textTheme.headline),
		  		new Text(desc, style: mediumText(context).copyWith(color: Colors.red)),
		  		new Text("Bitte versuche es später erneut")
		  	]
		  ),
		);
	}

	Widget _showFormList(BuildContext context) {
		var entries = <Widget>[
			new Text("Klasse auswählen", style: Theme.of(context).textTheme.headline),
			new Text(
					"Bitte wähle zunächst aus der Liste deine Klasse bzw. deine Stufe:",
					style: smallText(context)
			),
			const Divider()
		];

		for (var form in selector.allForms) {
			entries.add(
				new Container(
					height: 36.0,
				  child: new RadioListTile<data.Form>(
				  	title: new Text(form.name),
				  	dense: true,
				  	value: form,
				  	groupValue: selector.selectedForm,
				  	onChanged: onFormSelected),
				  ),
			);
		}

		return new SingleChildScrollView(
			child: new Padding(
				padding: const EdgeInsets.all(16.0),
			  child: new Column(
					crossAxisAlignment: CrossAxisAlignment.start,
			  	children: entries
			  ),
			)
		);
	}

	Widget _showCourseGroup(_CourseGroup group, BuildContext context) {
		Widget _buildForCourse(Course course) {
			return new Row(
				children: [
					new Text(course.name, style: Theme.of(context).textTheme.body2),
					new Text(" bei ${course.teacher.displayName}", style: smallText(context).copyWith(color: Colors.black54, fontStyle: FontStyle.italic))
				]
			);
		}

		String buildInfoText() {
			if (group.duplicateTeachers.isNotEmpty) {
				StringBuffer buff = new StringBuffer();
				buff.write("Achtung, ");
				for (var i = 0; i < group.duplicateTeachers.length; i++) {
					var dup = group.duplicateTeachers[i];

					if (i == group.duplicateTeachers.length - 1 && i > 0) {
						buff.write(" und ");
					} else if (i > 0) {
						buff.write(", ");
					}

					buff.write(dup.displayName);
				}

				if (group.duplicateTeachers.length > 1)
					buff.write(" unterrichten mehrere Kurse, bitte auf den genauen Namen achten");
				else
					buff.write(" unterrichtet mehrere Kurse, bitte auf den genauen Namen achten");
				return buff.toString();
			} else {
				if (group.supportsMulti)
					return "Bitte wähle eventuelle Zusatzkurse";
				return "Bitte wähle deinen ${group.title}-Kurs!";
			}
		}

		var entries = <Widget>[
			new Text(group.title, style: Theme.of(context).textTheme.headline),
			new Text(buildInfoText(), style: smallText(context)),
			const Divider()
		];

		for (var course in group.entries) {
			if (group.supportsMulti) {
				entries.add(
					new Container(
						key: new ObjectKey(course),
						height: 36.0,
						child: new CheckboxListTile(
							title: _buildForCourse(course),
							dense: true,
							value: selector.visibleSelected.contains(course),
							onChanged: (c) => onCourseMultiSelected(course, c)
						)
					)
			);
			} else {
				entries.add(
					new Container(
						key: new ObjectKey(course),
						height: 36.0,
						child: new RadioListTile<Course>(
							title: _buildForCourse(course),
							dense: true,
							value: course,
							groupValue: group.findSelected(selector),
							onChanged: (c) => onCourseSelected(c, group)
						),
					),
				);
			}
		}

		if (!group.supportsMulti) {
			entries.add(
				new Container(
					height: 24.0,
					key: new UniqueKey(),
					child: new RadioListTile<Course>(
							title: new Text("Ich belege keinen ${group.title}-Kurs"),
							dense: true,
							value: selector.noCourse,
							groupValue: group.findSelected(selector),
							onChanged: (c) => onCourseSelected(c, group)),
				),
			);
		}

		return new SingleChildScrollView(
				child: new Padding(
					padding: const EdgeInsets.all(16.0),
					child: new Column(
							crossAxisAlignment: CrossAxisAlignment.start,
							children: entries
					),
				)
		);
	}

  @override
  Widget build(BuildContext context) {
		PreferredSizeWidget progressIndicator;
		Widget bottomBar;
		Widget body;

		if (selector == null)
			init();

		if (selector.isError) {
			body = _showError(selector.error, context);
		} else {
			switch (selector.step) {
				case _CourseSelectionStep.FETCHING_FORMS:
					body = _showLoading("Liste mit Klassen wird geladen", context);
					break;
				case _CourseSelectionStep.DISPLAYING_FORMS:
					body = _showFormList(context);
					break;
				case _CourseSelectionStep.FETCHING_COURSES:
					body = _showLoading("Liste mit Fächern und Kursen wird geladen", context);
					break;
				case _CourseSelectionStep.DISPLAYING_COURSES:
					body = _showCourseGroup(selector.groups[selector.currentGroupIndex], context);

					progressIndicator = new _AppBarProgressIndicator((selector.currentGroupIndex + 1) / selector.groups.length);

					if (selector.currentGroupIndex < selector.groups.length - 1) {
						var prevListener = selector.currentGroupIndex > 0 ? previousStep : null;
						bottomBar = new BottomStepSelectionBar(prevListener, nextStep);
					} else {
						bottomBar = new BottomStepSelectionBar(
								previousStep, nextStep,
								"ZURÜCK", "ABSCHLIEẞEN");
					}
					break;
				case _CourseSelectionStep.SUBMITTING:
					body = _showLoading("Auswahl wird gespeichert", context);
					break;
			}
		}

		return new Scaffold(
			appBar: new AppBar(
				title: new Text('Klassen und Kurse'),
				bottom: progressIndicator,
			),
			body: body,
			bottomNavigationBar: bottomBar,
		);
  }
}

class BottomStepSelectionBar extends StatelessWidget {

	final VoidCallback onPreviousSelected;
	final VoidCallback onNextSelected;

	final String prevDesc;
	final String nextDesc;

	BottomStepSelectionBar(this.onPreviousSelected, this.onNextSelected, [this.prevDesc = "ZURÜCK", this.nextDesc = "WEITER"]);

  @override
  Widget build(BuildContext context) {
  	var theme = Theme.of(context);
  	var buttonText = theme.textTheme.button.copyWith(
				color: Colors.black54, fontWeight: FontWeight.bold);

  	var entries = <Widget>[];

  	if (onPreviousSelected != null) {
  		entries.add(
				new Expanded(
					child: new MaterialButton(
						padding: const EdgeInsets.only(),
						child: new Row(
							mainAxisSize: MainAxisSize.min,
							mainAxisAlignment: MainAxisAlignment.start,
							children: [
								new Icon(Icons.navigate_before, color: Colors.black54),
								new Text(prevDesc, style: buttonText)
							],
						),
						onPressed: onPreviousSelected,
					)
				),
			);
		} else {
  		entries.add(new Expanded(child: new Container()));
		}

  	if (onNextSelected != null) {
  		entries.add(
				new Expanded(
					child: new MaterialButton(
						padding: const EdgeInsets.only(),
						child: new Row(
							mainAxisSize: MainAxisSize.min,
							mainAxisAlignment: MainAxisAlignment.end,
							children: [
								new Text(nextDesc, style: buttonText),
								new Icon(Icons.navigate_next, color: Colors.black54),
							],
						),
						onPressed: onNextSelected,
					)
				)
			);
		} else {
  		entries.add(new Expanded(child: new Container()));
		}

    return new Container(
			height: 50.0,
			color: Colors.black12,
			child: new Row(
				mainAxisAlignment: MainAxisAlignment.spaceAround,
				children: entries
			)
		);
  }
}

class _AppBarProgressIndicator extends StatelessWidget implements PreferredSizeWidget {

	static const double HEIGHT = 5.0;

	final double percentage;

	_AppBarProgressIndicator(this.percentage);

	@override
	Size get preferredSize => new Size.fromHeight(HEIGHT);

  @override
  Widget build(BuildContext context) {
  	return new LayoutBuilder(builder: _buildSized);
  }

  Widget _buildSized(BuildContext context, BoxConstraints constraints) {
  	var totalWidth = constraints.maxWidth;
  	var mainWidth = percentage * totalWidth;
  	var offWidth = totalWidth - mainWidth;

  	var mainColor = percentage < 1 ? Colors.indigoAccent : Colors.green;

		return new Row(
				children: [
					new AnimatedContainer(
							width: mainWidth, height: HEIGHT, color: mainColor,
							duration: const Duration(milliseconds: 150)),
					new AnimatedContainer(
							width: offWidth, height: HEIGHT,
							color: Colors.indigoAccent.shade100,
							duration: const Duration(milliseconds: 150))
				]
		);
	}
}