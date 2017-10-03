import 'dart:async';

import 'package:azuchath_flutter/logic/data/lessons.dart';
import 'package:intl/intl.dart';

class ChangedData<T> {

	final T regular;
	final T actual;

	ChangedData.onlyRegular(this.regular, [this.actual]);

  ChangedData(this.regular, this.actual);

  ChangedData<E> map<E>(E f(T t)) {
		return new ChangedData(f(regular), f(actual));
	}

  bool hasChanged() => actual != null && regular != actual;
	bool bothNull() => regular == null && actual == null;

  T get current => actual ?? regular;
}

DateFormat formatDate = new DateFormat("yyyy-MM-dd");
DateFormat humanFormatDate = new DateFormat("dd.MM.yyyy");
DateFormat humanFormatDateShort = new DateFormat("dd.MM");
DateFormat humanFormatTime = new DateFormat("H:mm");

String getShortNameOfDay(int day) {
	switch (day) {
		case 0: return "Mo";
		case 1: return "Di";
		case 2: return "Mi";
		case 3: return "Do";
		case 4: return "Fr";
		case 5: return "Sa";
		case 6: return "So";
		default: return "??";
	}
}

String getNameOfDay(int day) {
	switch (day) {
		case 0: return "Montag";
		case 1: return "Dienstag";
		case 2: return "Mittwoch";
		case 3: return "Donnerstag";
		case 4: return "Freitag";
		case 5: return "Samstag";
		case 6: return "Sonntag";
		default: return "??";
	}
}

List<LessonTime> allHoursBetween(LessonTime start, LessonTime end, List<LessonHour> allHours, {inclusive: false}) {
	var hours = new List<LessonTime>();

	if (inclusive)
		hours.add(start);

	var current = start;
	while (true) {
		current = current.nextTime(allHours);
		if (current.isAfter(end, !inclusive))
			break;

		hours.add(current);
	}

	return hours;
}

typedef void TimeChangeCallback();

enum _MinuteListenerState {
	FAST, SLOW, PAUSED
}

class MinuteChangeListener {

	///We use two modes to listen for minute changes: When started, we check for
	///an updated minute every second. Once we found a change, we slow the period
	///down to 1min to report a subsequent change minutely.

	Timer ticker;
	_MinuteListenerState _state = _MinuteListenerState.PAUSED;

	LocalTime _currentMin;

	final TimeChangeCallback onMinuteChange;

	MinuteChangeListener(this.onMinuteChange);

	LocalTime _currentLocalTime() => new LocalTime.fromDate(new DateTime.now());

	bool isRunning() => _state != _MinuteListenerState.PAUSED;

	void start() {
		if (_state == _MinuteListenerState.PAUSED) {
			if (_currentMin != null) {
				//Timer restarted, check if time has changed since pause
				var now = _currentLocalTime();
				if (_currentMin.isBefore(now)) {
					onMinuteChange();
					//We don't switch to slow mode because we might have missed the exact
					//change of minute. This can lead to two changes being reported
					//quickly but that should be fine.
					_currentMin = now;
				}
			}

			_currentMin = _currentLocalTime();
			ticker = new Timer.periodic(const Duration(seconds: 1), _onTimerTick);
			_state = _MinuteListenerState.FAST;
		}
	}

	void pause() {
		if (_state != _MinuteListenerState.PAUSED) {
			if (ticker != null) {
				ticker.cancel();
				ticker = null;
			}
			_state = _MinuteListenerState.PAUSED;
		}
	}

	void _onTimerTick(Timer t) {
		if (_state == _MinuteListenerState.FAST) {
			var minNow = _currentLocalTime();
			if (minNow.isAfter(_currentMin)) {
				//Report first minute change and switch to slow mode
				_currentMin = minNow;
				ticker.cancel();

				ticker = new Timer.periodic(const Duration(minutes: 1), _onTimerTick);
				_state = _MinuteListenerState.SLOW;
				onMinuteChange();
			}
		} else if (_state == _MinuteListenerState.SLOW) {
			onMinuteChange();
		}
	}
}

///Calculates n!
int factorial(int n) {
	var p = 1;
	for (var i = 2; i <= n; i++) {
		p *= i;
	}
	return p;
}

double binomialCoefficient(int n, int k) {
	return factorial(n) / (factorial(k) * factorial(n - k));
}