import 'dart:async';

import 'package:azuchath_flutter/logic/azuchath.dart';
import 'package:azuchath_flutter/logic/data/messages.dart';
import 'package:azuchath_flutter/logic/io/message_socket.dart';
import 'package:azuchath_flutter/ui/ui_core.dart';
import 'package:azuchath_flutter/ui/ui_utils.dart';
import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';

class ConversationOverview extends StatefulWidget {

	final Azuchath _azu;

	MessageManager get _messages => _azu.messages;

	List<Conversation> get conversations {
		var conv = _messages.conversations.toList(growable: false);
		//Sort by last message id, descending
		conv.sort((c1, c2) {
			var id1 = _messages.lastMessage[c1]?.id ?? 0;
			var id2 = _messages.lastMessage[c2]?.id ?? 0;

			return -id1.compareTo(id2);
		});

		return conv;
	}

	ConversationOverview(this._azu);

  @override
  State<StatefulWidget> createState() => new _ConversationOverviewState();
}

class _ConversationOverviewState extends State<ConversationOverview> {

	StreamSubscription<Null> msgChangeListener;

	@override
	void initState() {
		super.initState();
		msgChangeListener = widget._messages.incomingMessageStream.listen((_) {
			setState(() {});
		});
	}

	@override
	void dispose() {
		super.dispose();
		msgChangeListener.cancel();
	}

	void _showConversation(Conversation c) {
		HUSScaffold.of(context).showConversation(c);
	}

	void _tryReconnect() {
		setState(() {
			widget._azu.connectWithChat();
		});
	}

	@override
	Widget build(BuildContext context) {
		var convs = widget.conversations;
		var myUserId = widget._azu.data.data.session.user.id;

		if (convs.isEmpty) {
			return new Center(
				child: new Column(
					mainAxisSize: MainAxisSize.max,
					mainAxisAlignment: MainAxisAlignment.center,
					children: [
						new Icon(Icons.settings_input_antenna, size: 50.0, color: Colors.black54,),
						new Text(
							"Keine Konversationen",
							textAlign: TextAlign.center,
							style: Theme.of(context).textTheme.display1.copyWith(color: Colors.black38),
						),
						new Text(
							"Die Nachrichtenfunktion wird schrittweise für alle Klassen eingeführt. "
							"Bitte habe noch etwas Gedult.",
							textAlign: TextAlign.center, style: new TextStyle(color: Colors.black54),
						),
					],
				),
			);
		}

		//Every second item will be a divider. We don't need one after the last
		//entry, so we would have 2n-1 elements with dividers at index n = 1, 3, 5
		var list = new ListView.builder(
			padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0).copyWith(bottom: 0.0),
			itemCount: convs.length * 2 - 1,
			itemBuilder: (context, i) {
				if (i % 2 == 1) {
					return const Divider();
				}

				var c = convs[i ~/ 2];
				var m = widget._messages.lastMessage[c];
				var sentByMe = myUserId == m?.sender?.id;

				return new ConversationHeader(c, m, () => _showConversation(c), sentByMe);
			}
		);

		bool hasError = widget._messages.currentError != null;
		if (hasError) {
			return new Column(
				crossAxisAlignment: CrossAxisAlignment.start,
				children: [
					new _ChatErrorInfo(widget._messages.currentError, _tryReconnect),
					new Expanded(child: list),
				]
			);
		}

		return list;
	}

}

class ConversationHeader extends StatelessWidget {

	final Conversation conversation;
	final TextMessage lastMessage;
	final bool lastMsgSentByMe;

	final VoidCallback onClick;

	ConversationHeader(this.conversation, this.lastMessage, this.onClick, [this.lastMsgSentByMe = false]);

	Widget _createTitle(BuildContext context) {
		var mainStyle = new TextStyle(color: Colors.black, fontSize: 18.0, fontWeight: FontWeight.w500);

		if (conversation.title != null) {
			return new Text(conversation.title, style: mainStyle);
		} else {
			//TODO Display form info for teachers
			return new Row(
				crossAxisAlignment: CrossAxisAlignment.baseline,
				textBaseline: TextBaseline.alphabetic,
				children: [
					new Text(conversation.course.displayName, style: mainStyle),
					new Text("(Kurs)", style: smallText(context)),
				],
			);
		}
	}

	Widget _lastMsgRow(BuildContext context) {
		var lastAuthor = lastMsgSentByMe ? "Du" : lastMessage.sender.displayName;
		var lastContent = lastMessage.content;

		var color = lastMsgSentByMe ? Colors.green :
			Colors.blue;

		return new Row(
			children: [
				new Container(width: 4.0),
				new Text(lastAuthor, style: new TextStyle(color: color)),
				new Flexible(
					child: new Text(
						": $lastContent",
						maxLines: 1,
						overflow: TextOverflow.ellipsis,
						style: smallText(context),
					)
				)
			],
		);
	}

  @override
  Widget build(BuildContext context) {
  	var rows = <Widget> [
  		_createTitle(context)
		];

		rows.add(new Container(height: 4.0)); //spacing

  	if (lastMessage != null) {
  		rows.add(_lastMsgRow(context));
		} else {
  		rows.add(
				new Center(
				  child: new Text(
				  	"Noch keine Nachrichten",
				  	style: smallText(context).copyWith(fontStyle: FontStyle.italic)
				  ),
				)
			);
		}

  	return new Material(
			type: MaterialType.canvas,
			child: new InkWell(
				onTap: onClick,
				child: new Column(
					crossAxisAlignment: CrossAxisAlignment.start,
					children: rows
				),
			),
		);
  }
}

class _ChatErrorInfo extends StatelessWidget {

	final MessageError error;
	final VoidCallback retryCb;

	_ChatErrorInfo(this.error, this.retryCb);

  @override
  Widget build(BuildContext context) {
  	var secondRowContent = <Widget> [
			new Flexible(
				child: new Text(
					error.message ?? "Ein unbekannter Fehler ist aufgetreten",
					style: smallText(context)
				)
			),
		];

  	if (error.canRetry) {
  		secondRowContent.add(
				new IconButton(
					padding: const EdgeInsets.all(4.0),
					onPressed: retryCb,
					color: Colors.lightBlue,
					icon: const Icon(Icons.refresh),
					tooltip: "Erneut versuchen",
				)
			);
		}

  	return new Material(
			elevation: 4.0,
		  color: Colors.white,
		  child: new Container(
				padding: const EdgeInsets.all(8.0).copyWith(bottom: 0.0),
		    child: new Column(
  				crossAxisAlignment: CrossAxisAlignment.start,
		    	children: [
		    		new Row(
		    			children: [
		    				new Icon(Icons.warning, color: Colors.yellow,),
		    				new Container(width: 4.0, height: 0.0),
		    				new Text("Keine Verbindung möglich", style: mediumText(context))
		    			]
		    		),
						new Row(
							mainAxisAlignment: MainAxisAlignment.spaceBetween,
							children: secondRowContent
						),
		    	]
		    ),
		  ),
		);
  }
}