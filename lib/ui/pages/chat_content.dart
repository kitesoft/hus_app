import 'dart:async';
import 'dart:math';

import 'package:azuchath_flutter/logic/azuchath.dart';
import 'package:azuchath_flutter/logic/data/messages.dart';
import 'package:azuchath_flutter/ui/ui_core.dart';
import 'package:azuchath_flutter/ui/ui_utils.dart';
import 'package:azuchath_flutter/utils.dart';
import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';

typedef void _SendCallback(String msg);

class ConversationMessages extends StatefulWidget {

	final Azuchath azu;
	final Conversation conversation;

	ConversationMessages(this.azu, this.conversation);

  @override
  State<StatefulWidget> createState() => new _ConversationState();
}

class _ConversationState extends State<ConversationMessages> {

	MessageManager get msgLogic => widget.azu.messages;

	List<Message> messages;
	bool get dataAvailable => messages != null;

	StreamSubscription<Null> _sub;

	@override
	void initState() {
		super.initState();

		_sub = msgLogic.incomingMessageStream.listen((_) => _onMessagesChanged());
		_loadMessages();
	}

	@override
	void dispose() {
		super.dispose();

		_sub.cancel();
	}

	void _loadMessages() {
		msgLogic.loadMessagesInConversation(widget.conversation).then((msgs) {
			//User has been removed from this conversation after an update
			var convIds = msgLogic.conversations.map((c) => c.id);
			if (!convIds.contains(widget.conversation.id)) {
				Navigator.of(context).pop();
				return;
			}

			setState(() {
				var user = widget.azu.data.data.session.user;

				List<Message> allMsgs = msgs.toList();
				var backlog = msgLogic.sendBacklog.
					where((e) => e.conversation.id == widget.conversation.id);

				if (backlog.isNotEmpty) {
					allMsgs.addAll(backlog.map((e) => e.toFakeMessage(user)));

					allMsgs.sort((m1, m2) => m1.sentAt.compareTo(m1.sentAt));
				}

				messages = allMsgs;
			});
		});
	}

	void _onMessagesChanged() {
		_loadMessages();
	}

	void sendMessage(String text) {
		msgLogic.sendMessage(text, widget.conversation);
	}

  @override
  Widget build(BuildContext context) {
		Widget content;

		var myUserId = widget.azu.data.data.session.user.id;

		if (dataAvailable) {
			content = new Column(
				mainAxisSize: MainAxisSize.max,
				children: [
					new Expanded(
						child: new Container(
							color: Colors.black12,
						  child: new ListView.builder(
						  	padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0).copyWith(bottom: 0.0),
						  	itemCount: messages.length,
						  	itemBuilder: (ctx, i) {
						  		var msg = messages[i];

						  		if (msg is TextMessage) {
						  			return new _TextMessageEntry(msg, myUserId == msg.sender.id);
						  		} else {
						  			return new Text("unbekannte Nachricht!?");
						  		}
						  	}
						  ),
						)
					),
					new _MessageComposer(sendMessage),
				],
			);
		} else {
			content = new Center(
				child: new Column(
					mainAxisSize: MainAxisSize.max,
					mainAxisAlignment: MainAxisAlignment.center,
					children: [
						new HUSLoadingIndicator(),
						new Text("Wird geladen", style: mediumText(context))
					]
				)
			);
		}

    return new HUSScaffold(
			widget.azu,
			title: widget.conversation.displayTitle,
			content: content
		);
  }
}

class _MessageComposer extends StatefulWidget {

	final _SendCallback cb;

	_MessageComposer(this.cb);

	@override
  State<StatefulWidget> createState() => new _MessageComposerState();
}

class _MessageComposerState extends State<_MessageComposer> {

	TextEditingController _controller = new TextEditingController();

	bool get canSend => _controller.text.trim().isNotEmpty;

	void _textChanged(String data) {
		setState(() {});
	}

	void _sendBtnPressed() {
		setState(() {
			if (canSend) {
				var text = _controller.text.trim();
				widget.cb(text);
				_controller.text = "";
			}
		});
	}

	@override
	Widget build(BuildContext context) {
		return new Material(
			elevation: 8.0,
			child: new Container(
				margin: const EdgeInsets.symmetric(horizontal: 8.0),
				child: new Row(
					children: [
						new Expanded(
							child: new TextField(
								onChanged: _textChanged,
								controller: _controller,
								decoration: const InputDecoration(
									hintText: "Nachricht verfassen"
								),
							)
						),
						new IconButton(
							color: Colors.green,
							icon: const Icon(Icons.send),
							onPressed: canSend ? _sendBtnPressed : null
						)
					],
				),
			),
		);
	}
}

class _TextMessageEntry extends StatelessWidget {

	final TextMessage msg;
	final bool sentByMe;

	_TextMessageEntry(this.msg, this.sentByMe);

  @override
  Widget build(BuildContext context) {
  	return new LayoutBuilder(builder: _buildSized);
  }

  Widget _buildSized(BuildContext context, BoxConstraints constraints) {
  	//Width of the message should be <= 3/4 * parent width, but still at least
		//200.0
		var maxWidth = max(constraints.maxWidth * 0.75, 200.0);

		var time = humanFormatTime.format(msg.sentAt);
		if (msg.isBacklog)
			time = "wird gesendet";

		var senderDesc = sentByMe ? "Du" : msg.sender.displayName;

		return new Row(
			mainAxisSize: MainAxisSize.max,
			mainAxisAlignment: sentByMe ? MainAxisAlignment.end : MainAxisAlignment.start,
			children: [
				new Container(
					margin: const EdgeInsets.symmetric(vertical: 4.0),
					child: new CustomPaint(
						painter: new _MsgBackgroundPainter(sentByMe),
						child: new Container(
							margin: const EdgeInsets.all(4.0),
							constraints: new BoxConstraints(maxWidth: maxWidth),
							child: new Column(
								crossAxisAlignment: CrossAxisAlignment.start,
								children: [
									new Row(
										mainAxisSize: MainAxisSize.min,
										children: [
											new Text(
												senderDesc,
												style: const TextStyle(
													fontWeight: FontWeight.bold,
													color: Colors.blue
												),
											),
											new Container(width: 4.0, height: 0.0),
											new Text(
												time, style: const TextStyle(fontStyle: FontStyle.italic),
												textAlign: TextAlign.end,
											),
										]
									),
									new Container(height: 4.0, width: 0.0,),
									new Text(msg.content)
								],
							),
						),
					),
				),
			],
		);
	}
}

class _MsgBackgroundPainter extends CustomPainter {

	static const _CORNER_RADIUS = 10.0;

	final bool sentByMe;

	_MsgBackgroundPainter(this.sentByMe);

  @override
  void paint(Canvas canvas, Size size) {
  	//The background of the message will consist of a rectangle with rounded
		//corners. The left (sent by others) or right (sent by me) corner will
		//be replaced by an arrow to form a message bubble

		var width = size.width;
		var height = size.height;

		var p = new Path();
		//Start at the bottom of the top-left corner
		p.moveTo(0.0, _CORNER_RADIUS);
		p.arcTo(
			new Rect.fromCircle(
				center: new Offset(_CORNER_RADIUS, _CORNER_RADIUS),
				radius: _CORNER_RADIUS
			), PI, PI / 2, false
		);
		//Move to top-right corner and draw circle
		p.lineTo(width - _CORNER_RADIUS, 0.0);
		p.arcTo(
			new Rect.fromCircle(
				center: new Offset(width - _CORNER_RADIUS, _CORNER_RADIUS),
				radius: _CORNER_RADIUS
			), 1.5 * PI, PI / 2, false
		);

		if (sentByMe) {
			//Bottom-right
			p.lineTo(width, height - 7.0);
			p.lineTo(width + 7.0, height);

			//Bottom-left
			p.lineTo(_CORNER_RADIUS, height);
			p.arcTo(
					new Rect.fromCircle(
							center: new Offset(_CORNER_RADIUS, height - _CORNER_RADIUS),
							radius: _CORNER_RADIUS
					), PI / 2, PI / 2, false
			);
		} else {
			//Bottom-right (round corner)
			p.lineTo(width, height - _CORNER_RADIUS);
			p.arcTo(
					new Rect.fromCircle(
						center: new Offset(width - _CORNER_RADIUS, height - _CORNER_RADIUS),
						radius: _CORNER_RADIUS,
					), 0.0, PI / 2, false
			);
			//Bottom-left
			p.lineTo(-7.0, height);
			p.lineTo(0.0, height - 10.0);
		}

		//finalize
		p.lineTo(0.0, _CORNER_RADIUS);

		var paint = new Paint();
		//color for outgoing messages: f0fddf
		paint.color = sentByMe ? new Color.fromARGB(0xff, 0xf0, 0xfd, 0xdf) : Colors.white;

		canvas.drawPath(p, paint);
		canvas.drawShadow(p, Colors.black, 16.0, false);
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) {
    return false;
  }
}