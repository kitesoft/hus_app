import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui';
import 'package:azuchath_flutter/logic/azuchath.dart';
import 'package:azuchath_flutter/logic/data/auth.dart';
import 'package:azuchath_flutter/logic/data/lessons.dart';
import 'package:azuchath_flutter/logic/data/usercontent.dart';
import 'package:azuchath_flutter/logic/io/message_socket.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:tuple/tuple.dart';

class MessageManager {

	Azuchath azu;

	MessageSocket socket;
	Database database;

	List<Conversation> conversations;
	Map<Conversation, ConversationMetaInfo> conversationMeta = new Map<Conversation, ConversationMetaInfo>();
	int get unreadMessages => conversationMeta.values.fold(0, (sum, c) => sum + c.unreadMessages);

	List<SendBacklogEntry> sendBacklog;

	MessageError currentError;
	bool get connected => currentError == null && socket.state != HandshakeState.ERROR;

	Stream<Null> get dataChangedStream => _dataController.stream;
	StreamController<Null> _dataController;
	Stream<Message> get incomingMessagesStream => _msgController.stream;
	StreamController<Message> _msgController;

	Future<File> get dbFile async {
		var dir = await getApplicationDocumentsDirectory();
		return new File("${dir.path}/hus_chat.db");
	}

	MessageManager(this.azu) {
		socket = new MessageSocket(this);

		_dataController = new StreamController<Null>.broadcast();
		_msgController = new StreamController<Message>.broadcast();
	}

	Conversation findConversationById(int id) {
		for (var c in conversations) {
			if (c.id == id)
				return c;
		}

		return null;
	}

	ConversationParticipant findParticipant(Conversation c, int userId) =>
			c.participants.firstWhere((p) => p.user.id == userId, orElse: () => null);

	Future initLocal() async {
		if (database != null) {
			print("Tried to call initLocal() with an established connection, closing");
			close();
		}

		Completer comp = new Completer();

		await openDatabase((await dbFile).path, version: 2,
			onCreate: (Database db, int version) {
				azu.handleMessageDbCreation();
				_handleDbChange(db, 0);
			},
			onUpgrade: (Database db, int oldVersion, int newVersion) {
				_handleDbChange(db, oldVersion);
			},
			onOpen: (Database db) async {
				database = db;
				await db.execute("PRAGMA foreign_keys = ON");
				await _loadBaseData();
				comp.complete();
			}
		);

		return comp.future;
	}

	void startConnecting() {
		socket.open();
	}

	Future _handleDbChange(Database db, int oldVersion) async {
		print("Upgrading database from version $oldVersion");

		if (oldVersion < 1) {
			//Create table known_users, storing info of users encountered
			await db.execute("""
CREATE TABLE known_users (
	id INT NOT NULL PRIMARY KEY,
	name VARCHAR(255) NOT NULL,
	verified BOOLEAN NOT NULL DEFAULT FALSE
)
			""");
			await db.execute("""
CREATE TABLE conversations (
	id INT NOT NULL PRIMARY KEY,
	title VARCHAR(255) NULL,
	associated_course INT NULL,
	last_meta_update INT NOT NULL,
	is_broadcast BOOLEAN NOT NULL DEFAULT FALSE
)
			""");
			await db.execute("""
CREATE TABLE participants (
	conversation INT NOT NULL,
	user INT NOT NULL,
	is_admin BOOLEAN NOT NULL DEFAULT FALSE,
	PRIMARY KEY (conversation, user)
	FOREIGN KEY (conversation) REFERENCES conversations(id),
	FOREIGN KEY (user) REFERENCES known_users(id)
)
			""");
			await db.execute("""
CREATE TABLE messages (
	id INT NOT NULL,
	conversation INT NOT NULL,
	sender INT NOT NULL,
	sent_at INT NOT NULL,
	msg_type VARCHAR(32) NOT NULL,
	content BLOB,
	PRIMARY KEY (id),
	FOREIGN KEY (conversation) REFERENCES conversations(id),
	FOREIGN KEY (sender) REFERENCES known_users(id)
)
			""");
			await db.execute(""" 
CREATE TABLE sending_backlog (
	id INT NOT NULL PRIMARY KEY,
	conversation INT NOT NULL,
	sent_at INT NOT NULL,
	content TEXT,
	
	FOREIGN KEY(conversation) REFERENCES conversations(id)
)
			""");
		}

		if (oldVersion < 2) {
			await db.execute("ALTER TABLE conversations ADD COLUMN last_read_message INT NOT NULL DEFAULT 0");
		}
	}

	Future _loadBaseData() async {
		//Load conversations
		var qConv = await database.query("conversations");
		var conversations = new List<Conversation>();

		var foundUsers = new Map<int, PublicUserInfo>();

		for (var row in qConv) {
			int id = row["id"];
			String title = row["title"];
			int courseId = row["associated_course"];
			int lastMetaUpdate = row["last_meta_update"];
			bool broadcast = row["is_broadcast"] == 1;

			var course = courseId != null ? azu.data.data.getCourseById(courseId) : null;
			conversations.add(new Conversation(id, title, course, lastMetaUpdate: lastMetaUpdate, isBroadcast: broadcast));
		}

		//Load participants for each conversation
		for (var conv in conversations) {
			var qPart = await database.rawQuery(
					"""
SELECT u.id, u.name, u.verified, p.is_admin FROM participants p
    INNER JOIN known_users u ON u.id = p.user
WHERE p.conversation = ?
					""", [conv.id]);

			for (var row in qPart) {
				int id = row["id"];
				var user = foundUsers.putIfAbsent(id, () {
					var name = row["name"];
					var verified = row["verified"] == 1;
					return new PublicUserInfo(id, name)..verified = verified;
				});

				var admin = row["is_admin"] == 1;

				conv.participants.add(new ConversationParticipant(user, admin));
			}
		}

		this.conversations = conversations;
		this.conversationMeta.clear();

		await _readConvMeta();
		await _readBacklog();
	}

	///Read amount of unread messages and last messages
	Future _readConvMeta() async {
		//For each conversation, select the latest message for a conversation overview
		var lastMessage = new Map<Conversation, TextMessage>();

		var latestMsgResult = await database.rawQuery("SELECT * FROM messages m WHERE m.id IN (SELECT MAX(id) FROM messages WHERE msg_type = 2 GROUP BY conversation)");
		for (var row in latestMsgResult) {
			TextMessage msg = _parseMessageFromDbRow(row);
			if (msg != null)
				lastMessage[msg.conversation] = msg;
		}

		//For each conversation, find the amount of unread messages
		var amountUnread = new Map<Conversation, int>();
		var query = """
SELECT COUNT(m.id) AS unread, c.id AS conversation FROM conversations c
	LEFT OUTER JOIN messages m ON m.conversation = c.id AND m.id > c.last_read_message
GROUP BY m.conversation
		""";
		var result = await database.rawQuery(query);
		for (var row in result) {
			var conversation = findConversationById(row["conversation"]);
			var unread = row["unread"];

			amountUnread[conversation] = unread;
		}

		for (var c in conversations) {
			var msg = lastMessage[c];
			var unread = amountUnread[c] ?? 0;

			conversationMeta[c] = new ConversationMetaInfo(unread, msg);
		}
	}

	Future _readBacklog() async {
		var backlogResult = await database.query("sending_backlog");
		this.sendBacklog = new List<SendBacklogEntry>();
		for (var row in backlogResult) {
			int id = row["id"];
			int conversationId = row["conversation"];
			DateTime sentAt = new DateTime.fromMillisecondsSinceEpoch(row["sent_at"]);
			String content = row["content"];

			sendBacklog.add(
				new SendBacklogEntry(
					id, findConversationById(conversationId), sentAt, content
				)
			);
		}
	}

	Future<List<Message>> loadMessagesInConversation(Conversation c) async {
		var sqlResult = await database.query("messages", where: "conversation = ?", whereArgs: [c.id], orderBy: "id");

		var msgs = new List<Message>();
		for (var row in sqlResult) {
			var msg = _parseMessageFromDbRow(row);
			msgs.add(msg);
		}

		return msgs;
	}

	Message _parseMessageFromDbRow(Map<String, dynamic> row) {
		int id = row["id"];
		int conversationId = row["conversation"];
		int senderId = row["sender"];
		DateTime sentAt = new DateTime.fromMillisecondsSinceEpoch(row["sent_at"]);
		int type = int.parse(row["msg_type"]);

		var data = JSON.decode(row["content"]);
		var conversation = findConversationById(conversationId);
		var participant = findParticipant(conversation, senderId);

		if (type == 1) {
			return null;
		} else if (type == 2) {
			return new TextMessage(id, conversation, participant.user, sentAt, data["text"]);
		}

		return null;
	}

	Tuple2<int, String> _writeMessageContent(Message msg) {
		String content;
		int type;

		if (msg is TextMessage) {
			type = 2;
			content = JSON.encode({"text": msg.content});
		} else if (msg is ParticipantsChangedMessage) {
			type = 1;
			content = "";
		}

		return new Tuple2(type, content);
	}

	Future writeIncomingMessage(Message msg) async {
		conversationMeta[msg.conversation]?.unreadMessages++;

		const sql = """
INSERT OR IGNORE INTO messages (id, conversation, sender, sent_at, msg_type, content)
VALUES (?, ?, ?, ?, ?, ?)
		""";

		var sentAt = msg.sentAt.millisecondsSinceEpoch;
		var meta = _writeMessageContent(msg);

		await database.rawInsert(sql, [msg.id, msg.conversation.id, msg.sender.id, sentAt, meta.item1, meta.item2]);
		if (msg is TextMessage)
			conversationMeta[msg.conversation].lastMessage = msg;
	}

	Future writeConversationMeta(List<int> allIds, List<Conversation> updated) async {
		var localIds = conversations.map((c) => c.id).toList();
		var removed = new List.from(localIds)..retainWhere((i) => !allIds.contains(i));
		var addedIds = new List.from(allIds)..removeWhere((i) => localIds.contains(i));
		var updatedOnly = new List<Conversation>.from(updated)..removeWhere((c) => removed.contains(c.id) || addedIds.contains(c.id));

		await database.inTransaction(() async {
			for (var r in removed) {
				//Delete all messages from this conversation, then conversation itself
				await database.delete("messages", where: "conversation = ?", whereArgs: [r]);
				await database.delete("sending_backlog", where: "conversation = ?", whereArgs: [r]);
				await database.delete("participants", where: "conversation = ?", whereArgs: [r]);
				await database.delete("conversations", where: "id = ?", whereArgs: [r]);

				var localConv = conversations.firstWhere((c) => c.id == r);
				conversations.remove(localConv);
			}
			for (var a in addedIds) {
				//Find associated conversation, which has to be in updated
				var conv = updated.firstWhere((c) => c.id == a);

				await database.insert("conversations", {
					"id": conv.id, "title": conv.title, "associated_course": conv.course?.id,
					"last_meta_update": conv.lastMetaUpdate, "is_broadcast": conv.isBroadcast ? 1 : 0
				});
				await _writeParticipants(conv);
				conversations.add(conv);
			}

			for (var u in updatedOnly) {
				await database.update("conversations", {
					"title": u.title, "associated_course": u.course?.id,
					"last_meta_update": u.lastMetaUpdate
				}, where: "id = ?", whereArgs: [u.id]);

				await _writeParticipants(u);
			}
		});

		await _readConvMeta();
		await _readBacklog(); //Might have changed if a conversation has been deleted
	}

	Future _writeParticipants(Conversation conv) async {
		await database.delete("participants", where: "conversation = ?", whereArgs: [conv.id]);

		const sqlUser = """
INSERT OR REPLACE INTO known_users (id, name, verified) VALUES (?, ?, ?)
		""";
		const sqlParticipant = """
INSERT OR REPLACE INTO participants (conversation, user, is_admin)
VALUES (?, ?, ?)
		""";

		for (var p in conv.participants) {
			await database.rawInsert(sqlUser, [p.user.id, p.user.displayName, p.user.verified]);
			await database.rawInsert(sqlParticipant, [conv.id, p.user.id, p.isAdmin ? 1 : 0]);
		}
	}

	Future sendMessage(String content, Conversation conversation) async {
		int id = sendBacklog.isEmpty ? 1 : sendBacklog.last.id + 1;

		SendBacklogEntry entry = new SendBacklogEntry(
			id, conversation, new DateTime.now(), content
		);

		await database.insert("sending_backlog",
			{"id": entry.id, "conversation": entry.conversation.id,
				"sent_at": entry.sentAt.millisecondsSinceEpoch, "content": entry.content}
		);
		sendBacklog.add(entry);

		broadcastUpdate();

		if (connected) {
			socket.sendBacklog();
		}
	}

	Future markConversationAsRead(Conversation conv) async {
		var query = "UPDATE conversations SET last_read_message = coalesce((SELECT MAX(id) FROM messages WHERE conversation = ?), 0) WHERE id = ?";

		await database.execute(query, [conv.id, conv.id]);
		conversationMeta[conv]?.unreadMessages = 0;
	}

	Future deleteFromBacklog(int id) {
		return database.delete("sending_backlog", where: "id = ?", whereArgs: [id]);
	}

	void broadcastUpdate({List<Message> newMessages}) {
	  _dataController.add(null);

	  if (newMessages != null) {
	  	newMessages.forEach(_msgController.add);
		}
	}

	void close() {
		socket?.close();
		database?.close();
		database = null;
	}

	void deleteLocalData() {
		close();
		closeStream();
		dbFile.then((f) => f.delete());
	}

	Future closeStream() async {
		await _dataController.close();
		await _msgController.close();
	}
}

class ConversationMetaInfo {

	int unreadMessages;
	TextMessage lastMessage;

	ConversationMetaInfo(this.unreadMessages, this.lastMessage);

}

class ConversationParticipant {

	final PublicUserInfo user;
	final bool isAdmin;

	ConversationParticipant(this.user, this.isAdmin);
}

class Conversation {

	final int id;
	String title;
	Course course;

	List<ConversationParticipant> participants = [];

	int lastMetaUpdate;
	bool isBroadcast;

	String get displayTitle => title ?? course.displayName;

	Conversation(this.id, this.title, this.course, {this.lastMetaUpdate, this.isBroadcast});
}

class SendBacklogEntry {

	final int id;
	final Conversation conversation;
	final DateTime sentAt;
	final String content;

	SendBacklogEntry(this.id, this.conversation, this.sentAt, this.content);

	TextMessage toFakeMessage(AuthenticatedUser user) {
		return new TextMessage(-1, conversation, user.toPublicInfo(), sentAt, content, isBacklog: true);
	}
}

abstract class Message {

	final int id;
	final Conversation conversation;

	final PublicUserInfo sender;
	final DateTime sentAt;

	Message(this.id, this.conversation, this.sender, this.sentAt);
}

class ParticipantsChangedMessage extends Message {

	final bool added;
	final PublicUserInfo user;

	ParticipantsChangedMessage(int id, Conversation conversation,
			PublicUserInfo sender, DateTime sentAt, this.added, this.user) :
				super(id, conversation, sender, sentAt);
}

class TextMessage extends Message {

	final String content;
	final bool isBacklog; //Not sent yet, just local

  TextMessage(int id, Conversation conversation, PublicUserInfo sender, DateTime sentAt, this.content, {this.isBacklog = false}) : super(id, conversation, sender, sentAt);

}

class MessageUtils {

	static Color colorForSender(PublicUserInfo sender, {Conversation inConversation}) {
		const colors = const [
			Colors.blue,
			Colors.red,
			Colors.green,
			Colors.yellow,
			Colors.purple,
			Colors.teal,
			Colors.orange,
		];
		Color getForIndex(int i) {
			return colors[i % colors.length];
		}

		if (inConversation != null) {
			for (var i = 0; i < inConversation.participants.length; i++) {
				var p = inConversation.participants[i];

				if (p.user.id == sender.id)
					return getForIndex(i);
			}
		}

		return getForIndex(sender.id);
	}

}