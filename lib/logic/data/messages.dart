import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:azuchath_flutter/logic/azuchath.dart';
import 'package:azuchath_flutter/logic/data/auth.dart';
import 'package:azuchath_flutter/logic/data/lessons.dart';
import 'package:azuchath_flutter/logic/data/usercontent.dart';
import 'package:azuchath_flutter/logic/io/message_socket.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:tuple/tuple.dart';

class MessageManager {

	Azuchath azu;

	MessageSocket socket;
	Database database;

	List<Conversation> conversations;
	Map<Conversation, TextMessage> lastMessage = new Map<Conversation, TextMessage>();
	List<SendBacklogEntry> sendBacklog;

	MessageError currentError;
	bool get connected => currentError == null && socket.state != HandshakeState.ERROR;

	Stream<Null> incomingMessageStream;
	StreamController<Null> _streamController;

	MessageManager(this.azu) {
		socket = new MessageSocket(this);

		_streamController = new StreamController<Null>.broadcast();
		incomingMessageStream = _streamController.stream;
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

		var dir = await getApplicationDocumentsDirectory();
		var file = new File("${dir.path}/hus_chat.db");

		Completer comp = new Completer();

		await openDatabase(file.path, version: 4,
			onCreate: (Database db, int version) {
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
	last_meta_update INT NOT NULL
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
		}
		if (oldVersion < 4) {
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

			var course = courseId != null ? azu.data.data.getCourseById(courseId) : null;
			conversations.add(new Conversation(id, title, course, lastMetaUpdate: lastMetaUpdate));
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
		this.lastMessage.clear();

		//For each conversation, select the latest message for a conversation overview
		var latestMsgResult = await database.rawQuery("SELECT * FROM messages m WHERE m.id = (SELECT MAX(id) FROM messages WHERE msg_type = 2 GROUP BY conversation)");
		for (var row in latestMsgResult) {
			var msg = _parseMessageFromDbRow(row);
			if (msg != null)
				lastMessage[msg.conversation] = msg;
		}

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
		const sql = """
INSERT OR IGNORE INTO messages (id, conversation, sender, sent_at, msg_type, content)
VALUES (?, ?, ?, ?, ?, ?)
		""";

		var sentAt = msg.sentAt.millisecondsSinceEpoch;
		var meta = _writeMessageContent(msg);

		await database.rawInsert(sql, [msg.id, msg.conversation.id, msg.sender.id, sentAt, meta.item1, meta.item2]);
		if (msg is TextMessage)
			lastMessage[msg.conversation] = msg;
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
				lastMessage.remove(localConv);
			}
			for (var a in addedIds) {
				//Find associated conversation, which has to be in updated
				var conv = updated.firstWhere((c) => c.id == a);

				await database.insert("conversations", {
					"id": conv.id, "title": conv.title, "associated_course": conv.course?.id,
					"last_meta_update": conv.lastMetaUpdate,
				});
				await _writeParticipants(conv);
				conversations.add(conv);
			}

			for (var u in updatedOnly) {
				await database.update("conversations", {
					"title": u.title, "associated_course": u.course.id,
					"last_meta_update": u.lastMetaUpdate
				}, where: "id = ?", whereArgs: [u.id]);

				await _writeParticipants(u);
			}
		});
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

	Future deleteFromBacklog(int id) {
		return database.delete("sending_backlog", where: "id = ?", whereArgs: [id]);
	}

	void broadcastUpdate() => _streamController.add(null);

	void close() {
		socket?.close();
		database?.close();
		database = null;
	}

	Future closeStream() {
		return _streamController.close();
	}
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

	String get displayTitle => title ?? course.displayName;

	Conversation(this.id, this.title, this.course, {this.lastMetaUpdate});
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
