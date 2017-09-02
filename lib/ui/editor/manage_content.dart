import 'dart:async';
import 'package:azuchath_flutter/logic/azuchath.dart';
import 'package:azuchath_flutter/logic/data/usercontent.dart';
import 'package:azuchath_flutter/ui/editor/homework.dart';
import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';

abstract class ContentManager<T extends StatefulWidget> extends State<T> {
	bool canBeCompleted();
	Future complete();
}

class ContentNavResponse {
	final bool success;

	const ContentNavResponse(this.success);
}

class AddContent extends StatefulWidget {

	final Azuchath azu;
	final dynamic toEdit;

	AddContent(this.azu, [this.toEdit]);

  @override
  State<AddContent> createState() => new AddContentState(azu, toEdit);
}

class AddContentState extends State<AddContent> {

	final GlobalKey<ContentManager> contentKey = new GlobalKey<ContentManager>();

	final Azuchath azu;
	final dynamic toEdit;

	AddContentState(this.azu, [this.toEdit]);

	void onCanFinishChanged() {
		setState(() => {});
	}

	Future complete() async {
		await contentKey.currentState.complete();
		Navigator.of(context).pop(const ContentNavResponse(true));
	}

  @override
  Widget build(BuildContext context) {
		var canBeFinished = contentKey.currentState != null && contentKey.currentState.canBeCompleted();
  	var actions = <Widget>[
  		new IconButton(
				icon: new Icon(Icons.done),
				tooltip: "Speichern",
				onPressed: canBeFinished ? complete : null
			)
		];

  	HomeworkEditor editor;
  	if (toEdit != null && toEdit is Homework) {
			editor = new HomeworkEditor.of(toEdit);
		} else {
			var user = new PublicUserInfo.fromUser(azu.data.data.session.user);
			editor = new HomeworkEditor.createNewHomework(user);
		}

		return new Scaffold(
			appBar: new AppBar(
				title: new Text('Neuer Inhalt'),
				actions: actions,
			),
			body: new EditHomework(azu, editor, onCanFinishChanged, key: contentKey)
		);
  }
}