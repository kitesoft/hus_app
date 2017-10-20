import 'dart:async';
import 'dart:math';

import 'package:azuchath_flutter/logic/azuchath.dart';
import 'package:azuchath_flutter/logic/data/lessons.dart';
import 'package:azuchath_flutter/logic/data/messages.dart';
import 'package:azuchath_flutter/logic/data/usercontent.dart';
import 'package:azuchath_flutter/ui/ui_core.dart';
import 'package:azuchath_flutter/ui/ui_utils.dart';
import 'package:azuchath_flutter/utils.dart';
import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';

typedef void _SendCallback(String msg);

class _DaySeparator {

	final DateTime date;

	_DaySeparator(this.date);

	String humanReadableText() {
		var today = LessonTime.normDate(new DateTime.now());

		var delta = today.difference(date);

		switch (delta.inDays) {
			case 0: return "HEUTE";
			case 1: return "GESTERN";
			case 2: return "VORGESTERN";
			default:
				var format = humanFormatDateShort.format(date);
				return format.toUpperCase();
		}
	}
}

class ConversationMessages extends StatefulWidget {

	final Azuchath azu;
	final Conversation conversation;

	ConversationMessages(this.azu, this.conversation);

  @override
  State<StatefulWidget> createState() => new _ConversationState();
}

class _ConversationState extends State<ConversationMessages> {

	MessageManager get msgLogic => widget.azu.messages;

	List<dynamic> entries; //types are either Message or _DaySeparator
	bool get dataAvailable => entries != null;

	ScrollController _scrollController = new ScrollController();

	StreamSubscription<Message> _sub;
	StreamSubscription<Duration> _startFrame;

	bool shouldScrollToBottom = true;
	double lastExtend;

	@override
	void initState() {
		super.initState();

		//As the conversation log has been opened, mark it as read
		msgLogic.markConversationAsRead(widget.conversation);

		_sub = msgLogic.incomingMessagesStream
				.where((msg) => msg.conversation.id == widget.conversation.id)
				.listen((_) => _onMessagesChanged());

		_loadMessages();

		/*
		Scrolling to the end of a ListView, is, is seems, almost impossible, and even
		though this solution kind of does what it's supposed to do, it's inelegant
		and quite slow, as it will require multiple frames (sometimes, the jumping
		is even visible to the user).
		The basic mechanism for scrolling to the end of a ListView is taken from this
		answer on StackOverflow: https://stackoverflow.com/a/44142234/3260197
		What this does is telling the ListView to use the lowest visible position
		(maxExtend) and use it as current offset, putting it to the top, or, if the
		end has been almost been reached, scrolls to the bottom of the list.
		The problem is that it will only be done once. When the list's total height
		is greater than 2 times the height of it's widget on the screen, this will
		not work. Our solution is to perform this step multiple times, giving the
		framework some time (a frame) to perform the jumping in between.
		 */

		_startFrame = widget.azu.onNewFrame.listen((_) {
			if (shouldScrollToBottom) {
				if (!_scrollController.hasClients)
					return; //Wait until the controller is attached

				var maxExtend = _scrollController.position.maxScrollExtent;

				if (lastExtend == null || maxExtend > lastExtend) {
					_scrollController.jumpTo(maxExtend);
					lastExtend = maxExtend;
				} else {
					//Last position reached
					shouldScrollToBottom = false;
					lastExtend = null;
				}
			}
		});
	}

	@override
	void dispose() {
		super.dispose();

		_sub.cancel();
		_startFrame.cancel();
	}

  @override
  Widget build(BuildContext context) {
		Widget content;

		var myUserId = widget.azu.data.data.session.user.id;

		if (dataAvailable) {
			var list = new Expanded(
				child: new Container(
					color: Colors.black12,
					child: new ListView.builder(
						controller: _scrollController,
						padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 8.0).copyWith(bottom: 0.0),
						itemCount: entries.length,
						itemBuilder: (ctx, i) {
							var msg = entries[i];

							if (msg is TextMessage) {
								return new _TextMessageEntry(msg, myUserId == msg.sender.id);
							} else if (msg is _DaySeparator) {
								return new _ChatInfoEntry(new Text(msg.humanReadableText()));
							} else {
								return new Text("unbekannte Nachricht!?");
							}
						}
					),
				)
			);
			var children = <Widget>[list];

			if (!widget.conversation.isBroadcast) {
				children.add(new _MessageComposer(sendMessage));
			}

			content = new Column(
				mainAxisSize: MainAxisSize.max,
				children: children
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
			content: content,
		);
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

				entries = new List<dynamic>.from(allMsgs);

				//Add an _DaySeparator for each date
				DateTime date;
				int amountInserted = 0;
				for (var i = 0; i < allMsgs.length; i++) {
					var msg = allMsgs[i];

					var msgDate = LessonTime.normDate(msg.sentAt);
					if (date == null || !msgDate.isAtSameMomentAs(date)) {
						date = msgDate;
						entries.insert(i + amountInserted, new _DaySeparator(msgDate));
						amountInserted++;
					}
				}
			});
		});
	}

	void _onMessagesChanged() {
		//If the incoming message was part of this conversation, consider it read
		msgLogic.markConversationAsRead(widget.conversation);

		_loadMessages();
	}

	void sendMessage(String text) {
		msgLogic.sendMessage(text, widget.conversation)
				.then((_) => setState(() {})); //state change happened by sending a message
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

		var additionalBgPadding = sentByMe ?
			const EdgeInsets.only(right: _MsgBackgroundPainter._WRITE_ARROW_OFFSET) :
			const EdgeInsets.only(left: _MsgBackgroundPainter._WRITE_ARROW_OFFSET);

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
							margin: const EdgeInsets.all(4.0).add(additionalBgPadding),
							constraints: new BoxConstraints(maxWidth: maxWidth),
							child: new Column(
								crossAxisAlignment: CrossAxisAlignment.start,
								children: [
									new Row(
										mainAxisSize: MainAxisSize.min,
										children: [
											new Text(
												senderDesc,
												style: new TextStyle(
													fontWeight: FontWeight.bold,
													color: MessageUtils.colorForSender(msg.sender, inConversation: msg.conversation)
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

class _ChatInfoEntry extends StatelessWidget {

	final Widget content;

	_ChatInfoEntry(this.content);

  @override
  Widget build(BuildContext context) {
		return new Row(
			mainAxisSize: MainAxisSize.max,
			mainAxisAlignment: MainAxisAlignment.center,
			children: [
				new Flexible(
					child: new Container(
						margin: const EdgeInsets.symmetric(vertical: 4.0),
						padding: const EdgeInsets.all(4.0),
						decoration: new BoxDecoration(
							color: Colors.lightBlue.withAlpha(128),
							borderRadius: const BorderRadius.all(const Radius.circular(5.0)),
						),
						child: new DefaultTextStyle(
							style: new TextStyle(fontWeight: FontWeight.w300, color: Colors.black87, letterSpacing: 1.5),
							child: content
						),
					),
				),
			],
		);
  }
}

///CustomPainter drawing a chat-bubble (rectangle with rounded corners).
class _MsgBackgroundPainter extends CustomPainter {

	static const _CORNER_RADIUS = 10.0;
	static const _WRITE_ARROW_OFFSET = 7.0;

	final bool sentByMe;

	_MsgBackgroundPainter(this.sentByMe);

  @override
  void paint(Canvas canvas, Size size) {
  	//The background of the message will consist of a rectangle with rounded
		//corners. The left (sent by others) or right (sent by me) corner will
		//be replaced by an arrow to form a message bubble

		var width = size.width;
		var height = size.height;

		var rectX0 = sentByMe ? 0.0 : _WRITE_ARROW_OFFSET;
		var rectXMax = sentByMe ? width - _WRITE_ARROW_OFFSET : width;

		var p = new Path();
		//Start at the bottom of the top-left corner
		p.moveTo(rectX0, _CORNER_RADIUS);
		p.arcTo(
			new Rect.fromCircle(
				center: new Offset(rectX0 + _CORNER_RADIUS, _CORNER_RADIUS),
				radius: _CORNER_RADIUS
			), PI, PI / 2, false
		);
		//Move to top-right corner and draw circle
		p.lineTo(rectXMax - _CORNER_RADIUS, 0.0);
		p.arcTo(
			new Rect.fromCircle(
				center: new Offset(rectXMax - _CORNER_RADIUS, _CORNER_RADIUS),
				radius: _CORNER_RADIUS
			), 1.5 * PI, PI / 2, false
		);

		if (sentByMe) {
			//Bottom-right
			p.lineTo(rectXMax, height - 10.0);
			p.lineTo(width, height);

			//Bottom-left
			p.lineTo(rectX0 + _CORNER_RADIUS, height);
			p.arcTo(
					new Rect.fromCircle(
							center: new Offset(rectX0 + _CORNER_RADIUS, height - _CORNER_RADIUS),
							radius: _CORNER_RADIUS
					), PI / 2, PI / 2, false
			);
		} else {
			//Bottom-right (round corner)
			p.lineTo(rectXMax, height - _CORNER_RADIUS);
			p.arcTo(
					new Rect.fromCircle(
						center: new Offset(rectXMax - _CORNER_RADIUS, height - _CORNER_RADIUS),
						radius: _CORNER_RADIUS,
					), 0.0, PI / 2, false
			);
			//Bottom-left
			p.lineTo(0.0, height);
			p.lineTo(rectX0, height - 10.0);
		}

		//finalize
		p.lineTo(rectX0, _CORNER_RADIUS);

		var paint = new Paint();
		//color for outgoing messages: f0fddf
		paint.color = sentByMe ? new Color.fromARGB(0xff, 0xf0, 0xfd, 0xdf) : Colors.white;

		canvas.drawPath(p, paint);
		canvas.drawShadow(p, Colors.black, 16.0, false);
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) => (oldDelegate is _MsgBackgroundPainter && oldDelegate.sentByMe == this.sentByMe) || true;
}