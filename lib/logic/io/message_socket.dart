import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:azuchath_flutter/logic/data/messages.dart';
import 'package:azuchath_flutter/logic/data/usercontent.dart';

enum HandshakeState {
	CONNECTING, WAITING_AUTH_RESPONSE, WAITING_SYNC_RESPONSE, ERROR
}

class MessageError {

	final String message;
	final bool canRetry;

	MessageError(this.message, this.canRetry);
}

class MessageSocket {

	//TODO Change to wss://chatapi.tutorialfactory.org/stream
	static const String CONNECTION_STR = "wss://chatapi.tutorialfactory.org/stream";

	WebSocket socket;
	StreamSubscription subscription;
	MessageManager messages;

	HandshakeState state = HandshakeState.CONNECTING;
	bool currentlySending = false;

	bool debug = false;

	MessageSocket(this.messages);

	Future open() async {
		try {
			state = HandshakeState.CONNECTING;
			messages.currentError = null;

			socket = await WebSocket.connect(CONNECTION_STR);
			subscription = socket.listen(_onMessage, onDone: () {
				if (debug)
					print("WebSocket closed");
				closeWithError(new MessageError("Verbindung unerwartet geschlossen", true));
			});
			_startHandshake();
		} catch (e, s) {
			print("Could not connect with server (io)");
			if (debug) {
				print(e);
				print(s);
			}

			closeWithError(new MessageError("Konnte nicht mit Server verbinden", true));
		}
	}

	void sendMessage(Map msg) {
		var data = JSON.encode(msg);
		if (debug)
			print("WS-TX: $data");
		socket.add(data);
	}

	void _startHandshake() {
		var token = messages.azu.data.data.session?.token;
		if (token == null) {
			closeWithError(new MessageError("Nicht angemeldet - bitte erneut probieren", true));
		}

		sendMessage({"type": 0, "token": token});
		state = HandshakeState.WAITING_AUTH_RESPONSE;
	}

	void _sendCatchUpRequest() {
		var lastMessageId = 0;
		var lastConversationUpdate = 0;

		if (messages.conversations.isNotEmpty) {
			for (var c in messages.conversations) {
				if (c.lastMetaUpdate > lastConversationUpdate)
					lastConversationUpdate = c.lastMetaUpdate;

				//TODO conversation meta only respects text messages, will have to update in future
				var lastMsgIdOfConv = messages.conversationMeta[c]?.lastMessage?.id ?? 0;
				if (lastMsgIdOfConv > lastMessageId)
					lastMessageId = lastMsgIdOfConv;
			}
		}

		sendMessage(
			{"type": 1, "last_message_id": lastMessageId,
				"last_conversation_update": lastConversationUpdate}
		);
		state = HandshakeState.WAITING_SYNC_RESPONSE;
	}

	void _onMessage(String msg) {
		if (debug) {
			print("WS-RX: $msg");
		}

		var data = JSON.decode(msg);

		var type = data["type"];
		switch (type) {
			case 0: //Malformed packet
				closeWithError(new MessageError("Protokollfehler, bitte später erneut probieren", false));
				return;
			case 1: //Auth response
				bool success = data["success"];
				if (!success) {
					closeWithError(new MessageError("Authentifizierung fehlgeschlagen", false));
					return;
				}
				_sendCatchUpRequest();
				break;
			case 2:
				_handleCatchUp(data);
				sendBacklog();
				break; //Catch-up old messages
			case 3:
				_handleIncomingMessage(data);
				break;
		}
	}

	Future _handleCatchUp(Map data) async {
		var allConversationIds = data["all_conversations"];
		var updatedConversations = new List<Conversation>();

		for (var conv in data["updated_conversations"]) {
			int id = conv["id"];
			String title = conv["title"];
			int courseId = conv["course"];
			int lastUpdate = conv["last_update"];
			bool broadcast = conv["is_broadcast"];

			var participants = new List<ConversationParticipant>();
			for (var p in conv["participants"]) {
				var userObj = p["user"];
				var user = new PublicUserInfo(userObj["id"], userObj["name"], verified: userObj["verified"]);
				participants.add(new ConversationParticipant(user, p["is_admin"]));
			}

			var course = courseId == null ? null : messages.azu.data.data.getCourseById(courseId);

			var found = messages.findConversationById(id);
			if (found != null) {
				found.title = title;
				found.course = course;
				found.lastMetaUpdate = lastUpdate;
				found.isBroadcast = broadcast;
			} else {
				found = new Conversation(id, title, course, lastMetaUpdate: lastUpdate, isBroadcast: broadcast);
			}

			found.participants = participants;
			updatedConversations.add(found);
		}

		await messages.writeConversationMeta(allConversationIds, updatedConversations);

		var foundMessages = <Message>[];
		for (var msg in data["messages"]) {
			var m = _parseMessage(msg);
			if (m != null)
				foundMessages.add(m);
		}

		for (var msg in foundMessages) {
			await messages.writeIncomingMessage(msg);
		}

		if (updatedConversations.isNotEmpty || foundMessages.isNotEmpty)
			messages.broadcastUpdate(newMessages: foundMessages);
	}

	Future _handleIncomingMessage(Map data) async {
		var msg = data["msg"];

		var m = _parseMessage(msg);
		if (m != null)
			await messages.writeIncomingMessage(m);

		messages.broadcastUpdate(newMessages: [m]);
	}

	Future sendBacklog() async {
		if (currentlySending)
			return;

		currentlySending = true;
		try {
			while (messages.sendBacklog.isNotEmpty) {
				var entry = messages.sendBacklog.first;

				sendMessage(
					{"type": 2, "content": entry.content,
						"conversation": entry.conversation.id}
				);

				messages.sendBacklog.remove(entry);
				await messages.deleteFromBacklog(entry.id);
			}
		} finally {
			currentlySending = false;
		}
	}

	Message _parseMessage(Map data) {
		int id = data["id"];
		int convId = data["conversation_id"];
		DateTime sendTime = new DateTime.fromMillisecondsSinceEpoch(data["sent_at"]);
		int senderId = data["sender_id"];

		var conversation = messages.findConversationById(convId);
		var sender = messages.findParticipant(conversation, senderId);

		if (conversation == null || sender == null)
			return null;

		switch (data["type"]) {
			case 2: //chat message
				var text = data["text"];
				return new TextMessage(id, conversation, sender.user, sendTime, text);
		}

		return null;
	}

	void closeWithError(MessageError error) {
		messages.currentError = error;
		state = HandshakeState.ERROR;
		close();
		messages.broadcastUpdate();
	}

	void close() {
		socket?.close();
		subscription?.cancel();
		state = HandshakeState.ERROR;
		currentlySending = false;
	}
}