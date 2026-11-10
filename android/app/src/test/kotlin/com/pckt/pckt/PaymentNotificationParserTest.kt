package com.pckt.pckt

import com.pckt.pckt.PaymentNotificationParser.Result
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class PaymentNotificationParserTest {
    private fun payment(title: String, text: String) = PaymentNotificationParser.parse(title, text) as Result.Payment
    private fun ignored(title: String, text: String) = assertTrue(
        "$title / $text should be ignored",
        PaymentNotificationParser.parse(title, text) is Result.Ignored,
    )

    @Test fun paidTo() {
        val p = payment("Payment successful", "You paid ₹250 to Swiggy")
        assertEquals(25000L, p.amountMinor)
        assertEquals(false, p.credit)
        assertEquals("Swiggy", p.merchant)
    }

    @Test fun amountFirstWithPaise() {
        val p = payment("₹1,234.50 paid to Asha Stores", "Using Axis Bank")
        assertEquals(123450L, p.amountMinor)
        assertEquals("Asha Stores", p.merchant)
    }

    @Test fun rsSpelling() = assertEquals(9900L, payment("", "Rs. 99 sent to Ravi via UPI").amountMinor)

    @Test fun nameStopsAtTrailingWords() = assertEquals("Blinkit", payment("", "₹500 paid to Blinkit successfully").merchant)

    @Test fun paymentOfSuccessful() {
        val p = payment("", "Payment of ₹60 to Tea Stall was successful")
        assertEquals(6000L, p.amountMinor)
        assertEquals("Tea Stall", p.merchant)
    }

    @Test fun merchantFromTitle() = assertEquals("Zudio", payment("Zudio", "₹800 paid").merchant)

    @Test fun receivedFrom() {
        val p = payment("", "You received ₹1,000 from Neha")
        assertEquals(true, p.credit)
        assertEquals("Neha", p.merchant)
    }

    @Test fun sentYou() {
        val p = payment("", "Rahul sent you ₹300")
        assertEquals(true, p.credit)
        assertEquals("Rahul", p.merchant)
    }

    @Test fun ownBankIsNotAMerchant() = assertEquals(null, payment("", "₹300 sent to your bank account").merchant)

    @Test fun paymentWithCashbackMentionStillCounts() {
        val p = payment("", "You paid ₹200 to Cafe. You won cashback!")
        assertEquals(20000L, p.amountMinor)
    }

    @Test fun ignoresFailed() = ignored("Payment failed", "₹250 to Swiggy could not be completed")

    @Test fun ignoresPending() = ignored("", "Your payment of ₹250 to Swiggy is pending")

    @Test fun ignoresRequests() = ignored("", "Neha requested ₹500 from you")

    @Test fun ignoresReminders() = ignored("", "Your electricity bill of ₹900 is due. Pay now")

    @Test fun ignoresPromotions() {
        ignored("Big offer!", "Get ₹100 cashback on your next payment")
        ignored("", "Win up to ₹5000 rewards today")
    }

    @Test fun ignoresBalance() = ignored("", "Your balance is ₹5,000")

    @Test fun ignoresNoAmount() = ignored("Paytm", "You paid someone")

    @Test fun shapeHidesNamesAndNumbers() {
        val shape = PaymentNotificationParser.shape("Asha", "You paid ₹250 to Neha 9876543210")
        assertEquals("x | you paid ₹9 to x 9", shape)
    }
}
