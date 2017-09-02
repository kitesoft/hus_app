import 'package:azuchath_flutter/logic/azuchath.dart';
import 'package:azuchath_flutter/logic/data/auth.dart';
import 'package:azuchath_flutter/logic/data/lessons.dart';
import 'package:azuchath_flutter/logic/data/usercontent.dart';
import 'package:azuchath_flutter/ui/ui_utils.dart';
import 'package:azuchath_flutter/utils.dart';
import 'package:flutter/material.dart';

enum _HomeworkAction {
	EDIT, DELETE, TOGGLE_COMPLETION
}

typedef void _HomeworkActionListener(Homework hw, _HomeworkAction action);
typedef void HomeworkEditListener(Homework hw);

class HomeworkCard extends StatelessWidget {

	final Homework hw;
	final AuthenticatedUser authenticatedUser;
	final _HomeworkActionListener _listener;

	HomeworkCard(this.hw, this.authenticatedUser, this._listener, {Key key}) : super(key: key);

	Widget buildPopupMenu(BuildContext ctx) {
		return new Container(
			width: 36.0,
			height: 36.0,
			child: new PopupMenuButton(
					onSelected: (val) {
						if (_listener != null)
							switch (val) {
								case 0: _listener(hw, _HomeworkAction.EDIT); break;
								case 1: _listener(hw, _HomeworkAction.DELETE); break;
							}
					},
					itemBuilder: (ctx) => [
						const PopupMenuItem(value: 0, child: const Text("Bearbeiten")),
						const PopupMenuItem(value: 1, child: const Text("Löschen"))
					]
			)
		);
	}

	Widget _getCourseWidget(BuildContext context) {
		if (authenticatedUser.type == AccountType.TEACHER) {
			return new Row(
				mainAxisSize: MainAxisSize.min,
				crossAxisAlignment: CrossAxisAlignment.baseline,
				textBaseline: TextBaseline.alphabetic,
				children: [
					new Text(
						hw.course.displayName,
						style: Theme.of(context).textTheme.title
					),
					new Container(
						margin: const EdgeInsets.symmetric(horizontal: 2.0),
					  child: new Text(
					  	"bei",
					  	style: smallText(context)
					  ),
					),
					new Text(
						hw.course.formName ?? "mehreren",
						style: Theme.of(context).textTheme.body2
					)
				],
			);
		} else {
			return new Text(
				hw.course.displayName,
				style: Theme.of(context).textTheme.headline
			);
		}
	}

	String _getInfoText() {
		var publishedByMe = hw.creator.id == authenticatedUser.id;
		var publisherText = publishedByMe ?
			(hw.published ? "von mir" : "nicht veröffentlicht") :
			"von ${hw.creator.displayName}";

		var date = humanFormatDateShort.format(hw.due);
		return "$publisherText • $date";
	}

  @override
  Widget build(BuildContext context) {
		var infoRowChildren = <Widget> [
			new Flexible(
				child: new Text(
					_getInfoText(),
					textAlign: TextAlign.right,
					style: smallText(context).copyWith(color: Colors.black)
				)
			),
		];

		if (hw.creator.id == authenticatedUser.id || authenticatedUser.type == AccountType.TEACHER)
			infoRowChildren.add(buildPopupMenu(context));
		else //Add some space on the right
			infoRowChildren.add(new Container(width: 8.0));

		var contentChildren = <Widget>[
			new Expanded(
				child: new Text(hw.content, style: mediumText(context))
			)
		];
		if (authenticatedUser.type == AccountType.STUDENT) {
			contentChildren.add(new Container(
				width: 36.0,
				height: 36.0,
				margin: const EdgeInsets.only(right: 8.0),
				child: new IconButton(
					color: hw.completed ? Colors.green : Colors.grey,
					icon: new Icon(Icons.done),
					onPressed: () => _listener(hw, _HomeworkAction.TOGGLE_COMPLETION)
				)
			));
		}

    return new Card(
			child: new Container(
				padding: const EdgeInsets.only(left: 16.0, bottom: 16.0),
				child: new Column(
					children: [
						new Row(
							mainAxisAlignment: MainAxisAlignment.spaceBetween,
							crossAxisAlignment: CrossAxisAlignment.center,
							textBaseline: TextBaseline.ideographic,
							children: [
								new Container(
									margin: const EdgeInsets.only(top: 16.0),
									child: new Hero(
										tag: hw.heroCourse,
										child: _getCourseWidget(context),
									),
								),
								new Expanded(
									child: new Row(
										mainAxisAlignment: MainAxisAlignment.end,
										children: infoRowChildren,
									)
								)
							]
						),
						new Row(
							crossAxisAlignment: CrossAxisAlignment.end,
							children: contentChildren
						)
					]
				)
			)
		);
  }
}

class EmptyHomeworkWidget extends StatelessWidget {

	final VoidCallback onEntryAdd;

	EmptyHomeworkWidget(this.onEntryAdd);

  @override
  Widget build(BuildContext context) {
    return new Center(
			child: new Container(
					padding: const EdgeInsets.all(8.0),
					child: new Column(mainAxisAlignment: MainAxisAlignment.center,
							children: [
								new Icon(
										Icons.weekend,
										size: 56.0,
										color: Colors.black54
								),
								new Text("Nichts zu tun", style: Theme.of(context).textTheme.headline.copyWith(color: Colors.black45)),
								new Text(
										"Entweder du hast wirklich nichts zu tun (Glückwunsch), " +
										"oder du kannst hier einen Eintrag hinzufügen",
										style: mediumText(context).copyWith(color: Colors.black45),
										textAlign: TextAlign.center,
								),
								new FlatButton(
										onPressed: onEntryAdd,
										child: new Text("NEUER EINTRAG", style: new TextStyle(color: Colors.blue))
								)
							]
					)
			)
		);
  }
}

class HomeworkOverview extends StatefulWidget {

	final Azuchath _azu;
	final HomeworkEditListener onHwEdit;
	final HomeworkEditListener onHwDelete;

	HomeworkOverview(this._azu, this.onHwEdit, this.onHwDelete);

  @override
  State<StatefulWidget> createState() => new HomeworkState(_azu, onHwEdit, onHwDelete);
}

class HomeworkState extends State<HomeworkOverview> {

	final Azuchath _azu;
	final HomeworkEditListener onHwEdit;
	final HomeworkEditListener onHwDelete;

	HomeworkState(this._azu, this.onHwEdit, this.onHwDelete);

	void homeworkAction(Homework hw, _HomeworkAction action) {
		if (action == _HomeworkAction.EDIT)
			onHwEdit(hw);
		if (action == _HomeworkAction.DELETE) {
			onHwDelete(hw);
			setState(() {
				hw.syncStatus = HomeworkSyncStatus.DELETED;
				_azu.data.setHomeworkModified();
			});
		}
		if (action == _HomeworkAction.TOGGLE_COMPLETION) {
			setState(() {
				hw.completed = !hw.completed;
				hw.completedSynced = false;
				_azu.data.setHomeworkModified();
			});
		}
	}

  @override
  Widget build(BuildContext context) {
  	var widgets = <Widget>[];

  	var today = LessonTime.normDate(new DateTime.now());
  	var allHw = new List<Homework>.from(_azu.data.data.homework.where((hw) {
  		return hw.syncStatus != HomeworkSyncStatus.DELETED &&
					(hw.due.isAfter(today) || hw.due == today);
		}));

		allHw.sort((a, b) => a.due.compareTo(b.due));
		allHw.sort((a, b) => a.completed ? (b.completed ? 0 : 1) : (b.completed ? -1 : 0));

		var completeCount = allHw.where((hw) => hw.completed).length;

		bool empty = true;
		bool completedSeparatorIncluded = false;

		for (var hw in allHw) {
			if (hw.completed && !completedSeparatorIncluded) {
				completedSeparatorIncluded = true;

				widgets.add(
					new Container(
						margin: const EdgeInsets.all(8.0),
						child: new Text(
							"Bereits erledigt (${completeCount})",
							style: Theme.of(context).textTheme.display1.copyWith(fontSize: 20.0),
						)
					)
				);
			}

			widgets.add(
					new HomeworkCard(hw, _azu.data.data.session.user, homeworkAction, key: new UniqueKey()));
			empty = false;
		}

		if (empty)
			return new EmptyHomeworkWidget(() => onHwEdit(null));

		//Add some padding at the bottom so that the actions are reachable even with
		//the FAB around
		widgets.add(new Container(height: 50.0));

		//A ListView causes some items to disappear for reasons I don't understand,
		//this acts as an ugly workaround.
		return new SingleChildScrollView(
			child: new Column(
				crossAxisAlignment: CrossAxisAlignment.start,
				children: widgets
			)
		);
  }

}