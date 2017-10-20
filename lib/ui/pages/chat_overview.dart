import 'dart:async';

import 'package:azuchath_flutter/logic/azuchath.dart';
import 'package:azuchath_flutter/logic/data/auth.dart';
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
			var id1 = _messages.conversationMeta[c1]?.lastMessage?.id ?? 0;
			var id2 = _messages.conversationMeta[c2]?.lastMessage?.id ?? 0;

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
		msgChangeListener = widget._messages.dataChangedStream.listen((_) {
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
		var user = widget._azu.data.data.session.user;
		var myUserId = user.id;
		var isTeacher = user.type == AccountType.TEACHER;

		Widget content;

		if (convs.isEmpty) {
			content = new Center(
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
		} else {
			//Every second item will be a divider. We don't need one after the last
			//entry, so we would have 2n-1 elements with dividers at index n = 1, 3, 5
			content = new ListView.builder(
				padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0).copyWith(bottom: 0.0),
				itemCount: convs.length * 2 - 1,
				itemBuilder: (context, i) {
					if (i % 2 == 1) {
						return const Divider();
					}

					var c = convs[i ~/ 2];
					var m = widget._messages.conversationMeta[c];
					var sentByMe = myUserId == m?.lastMessage?.sender?.id;

					return new ConversationHeader(c, m, () => _showConversation(c), sentByMe, isTeacher);
				}
			);
		}

		bool hasError = widget._messages.currentError != null;
		if (hasError) {
			return new Column(
				crossAxisAlignment: CrossAxisAlignment.start,
				children: [
					new _ChatErrorInfo(widget._messages.currentError, _tryReconnect),
					new Expanded(child: content),
				]
			);
		}

		return content;
	}

}

class ConversationHeader extends StatelessWidget {

	final Conversation conversation;
	final ConversationMetaInfo meta;

	TextMessage get lastMessage => meta?.lastMessage;
	int get unreadMessagesCount => meta?.unreadMessages ?? 0;

	final bool lastMsgSentByMe;
	final bool showForTeacher;

	final VoidCallback onClick;

	ConversationHeader(this.conversation, this.meta, this.onClick, [this.lastMsgSentByMe = false, this.showForTeacher = false]);

	Row _createTitle(BuildContext context) {
		var mainStyle = new TextStyle(color: Colors.black, fontSize: 18.0, fontWeight: FontWeight.w500);

		var courseDesc = "(Kurs)";
		if (showForTeacher && conversation.course != null) {
			courseDesc = "(Kurs mit ${conversation.course.formName ?? "mehreren"})";
		}

		var children = <Widget>[];

		if (conversation.isBroadcast) {
			children.add(new Icon(Icons.drafts, color: Colors.green,));
		}
		if (conversation.title != null) {
			children.add(new Text(conversation.title, style: mainStyle));
		} else {
			children.add(new Text(conversation.course.displayName, style: mainStyle));
			children.add(new Text(courseDesc, style: smallText(context)));
		}

		return new Row(
			crossAxisAlignment: CrossAxisAlignment.end,
			textBaseline: TextBaseline.alphabetic,
			children: children,
		);
	}

	Widget _lastMsgRow(BuildContext context) {
		var lastAuthor = lastMsgSentByMe ? "Du" : lastMessage.sender.displayName;
		var lastContent = lastMessage.content;

		//We don't use the color of this sender for the specific conversation so that
		//the same sender will always have the same color in this overview.
		var color = MessageUtils.colorForSender(lastMessage.sender);

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
		var topRow = _createTitle(context);

		var rows = <Widget> [topRow];
		rows.add(new Container(height: 4.0)); //spacing

  	if (lastMessage != null) {
  		rows.add(_lastMsgRow(context));
		} else {
  		rows.add(
				new Row(
				  children: [
						new Container(width: 4.0),
				    new Text(
				    	"Noch keine Nachrichten",
				    	style: smallText(context).copyWith(fontStyle: FontStyle.italic)
				    ),
				  ],
				),
			);
		}

		Widget mainContent = new Column(
			crossAxisAlignment: CrossAxisAlignment.start,
			children: rows,
		);


  	if (unreadMessagesCount > 0) {
  		mainContent = new Stack(
				children: [
					mainContent,
					new Positioned(
						top: 0.0, right: 0.0,
						child: new Container(
							alignment: Alignment.center,
							padding: const EdgeInsets.all(6.0),
							decoration: new BoxDecoration(
								color: Theme.of(context).primaryColor,
								shape: BoxShape.circle,
							),
							child: new Text(
								"$unreadMessagesCount",
								style: new TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16.0),
							),
						)
					)
				],
			);
		}

  	return new Material(
			type: MaterialType.canvas,
			child: new InkWell(
				onTap: onClick,
				child: mainContent,
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