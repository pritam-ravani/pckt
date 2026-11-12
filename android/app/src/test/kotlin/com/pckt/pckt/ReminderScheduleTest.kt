package com.pckt.pckt

import com.pckt.pckt.ReminderSchedule.Slot
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test
import java.util.Calendar
import java.util.GregorianCalendar

class ReminderScheduleTest {
    private val everyDay = (1..7).toSet()

    /** 10 Nov 2026 is a Tuesday. */
    private fun at(day: Int, hour: Int, minute: Int): Calendar =
        GregorianCalendar(2026, Calendar.NOVEMBER, day, hour, minute, 0).apply { set(Calendar.MILLISECOND, 0) }

    private fun assertNext(expected: Calendar, slots: List<Slot>, now: Calendar) =
        assertEquals(expected.time, java.util.Date(ReminderSchedule.next(slots, now)!!))

    @Test fun laterToday() = assertNext(at(10, 21, 0), listOf(Slot(21, 0, everyDay)), at(10, 9, 0))

    @Test fun tomorrowOncePassed() = assertNext(at(11, 9, 0), listOf(Slot(9, 0, everyDay)), at(10, 10, 0))

    @Test fun exactlyNowMovesOn() = assertNext(at(11, 9, 0), listOf(Slot(9, 0, everyDay)), at(10, 9, 0))

    @Test fun soonestOfMany() =
        assertNext(at(10, 14, 0), listOf(Slot(21, 0, everyDay), Slot(14, 0, everyDay), Slot(9, 0, everyDay)), at(10, 10, 0))

    @Test fun skipsOtherDays() = assertNext(at(14, 9, 0), listOf(Slot(9, 0, setOf(6))), at(10, 10, 0))

    @Test fun sundayIsSeven() = assertNext(at(15, 9, 0), listOf(Slot(9, 0, setOf(7))), at(10, 10, 0))

    @Test fun sameWeekdayNextWeekOncePassed() = assertNext(at(17, 9, 0), listOf(Slot(9, 0, setOf(2))), at(10, 10, 0))

    @Test fun nothingScheduled() = assertNull(ReminderSchedule.next(emptyList(), at(10, 10, 0)))
}
