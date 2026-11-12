package com.pckt.pckt

import java.math.BigDecimal
import java.util.Locale

/**
 * Reads a payment app's notification. Pure Kotlin so it can be unit tested.
 * It prefers missing a payment over inventing one: anything that isn't
 * clearly a completed payment is ignored.
 */
object PaymentNotificationParser {
    sealed class Result {
        data class Payment(val amountMinor: Long, val credit: Boolean, val merchant: String?) : Result()
        data class Ignored(val reason: String) : Result()
    }

    private val amount = Regex("(?:₹|\\brs\\.?|\\binr)\\s*([0-9][0-9,]*(?:\\.[0-9]{1,2})?)", RegexOption.IGNORE_CASE)

    private val notFinished = Regex(
        "\\b(failed|failure|declined|unsuccessful|pending|processing|in progress|requests?|requested|requesting|" +
            "remind\\w*|due|will be|scheduled|mandate|autopay|expir\\w*|balance|kyc)\\b"
    )
    private val promo = Regex(
        "% off|\\b(offers?|cashback|rewards?|scratch|win|won|coupons?|vouchers?|discounts?|loans?|insurance|" +
            "invest\\w*|gold|recharge now|pay now|pay again)\\b"
    )

    private val creditWords = Regex(
        "\\b(sent you|paid you|you received|received from|money received|credited|added to your)\\b|received\\s+(?:₹|rs|inr)"
    )
    private val debitWords = Regex(
        "\\b(you paid|paid to|paid|you sent|sent to|sent|debited)\\b|payment\\b.{0,40}\\b(successful|complete|completed|done)\\b"
    )

    private const val NAME = "([\\p{L}0-9&'._ -]{2,40}?)"
    private const val NAME_END = "(?=\\s+(?:on|via|using|from|successfully|is|was|has|at|for|with)\\b|\\s*[.!,|•:]|\\s*$)"
    private val toName = Regex("\\bto\\s+$NAME$NAME_END", RegexOption.IGNORE_CASE)
    private val fromName = Regex("\\bfrom\\s+$NAME$NAME_END", RegexOption.IGNORE_CASE)
    private val senderFirst = Regex("^$NAME\\s+(?:sent|paid)\\s+you\\b", RegexOption.IGNORE_CASE)
    private val genericTitle = Regex(
        "payment|successful|paytm|phonepe|google pay|gpay|money|sent|received|transaction|upi|₹|\\brs\\b|paid",
        RegexOption.IGNORE_CASE,
    )

    fun parse(title: String, text: String): Result {
        val clean = text.replace(Regex("\\s+"), " ").trim()
        val head = title.replace(Regex("\\s+"), " ").trim()
        val all = "$head $clean".trim()
        val lower = all.lowercase(Locale.ROOT)

        if (notFinished.containsMatchIn(lower)) return Result.Ignored("not finished")

        val match = amount.find(all) ?: return Result.Ignored("no amount")
        val value = match.groupValues[1].replace(",", "").toBigDecimalOrNull()
            ?: return Result.Ignored("no amount")
        if (value <= BigDecimal.ZERO) return Result.Ignored("no amount")

        val credit = creditWords.containsMatchIn(lower)
        if (!credit && !debitWords.containsMatchIn(lower)) return Result.Ignored("no payment words")
        // Promotions often mention an amount; a real payment still names one side.
        val explicit = Regex("\\b(you paid|paid to|sent to|you sent|sent you|paid you|received from|you received)\\b")
        if (promo.containsMatchIn(lower) && !explicit.containsMatchIn(lower)) return Result.Ignored("promotion")

        val minor = value.movePointRight(2).toLong()
        return Result.Payment(minor, credit, merchant(head, clean, credit))
    }

    private fun merchant(title: String, text: String, credit: Boolean): String? {
        for (source in listOf(text, title)) {
            val found = (if (credit) senderFirst.find(source) ?: fromName.find(source) else toName.find(source))
                ?.groupValues?.get(1)?.trim()
            if (found != null && !found.startsWith("your ", ignoreCase = true)) return found
        }
        return title.takeIf { it.length in 2..40 && !genericTitle.containsMatchIn(it) }
    }

    private val keep = setOf(
        "you", "paid", "to", "from", "sent", "received", "payment", "successful", "successfully", "of", "on", "via",
        "using", "money", "your", "bank", "account", "credited", "debited", "upi", "is", "was", "has", "been", "for",
        "the", "at", "a", "transaction", "completed", "complete", "done", "failed", "pending", "request", "offer",
        "cashback", "rs", "inr", "paytm", "phonepe", "google", "pay", "gpay", "by", "and", "reward", "balance",
    )

    /** The notification's wording with names and numbers hidden, safe to log for tuning. */
    fun shape(title: String, text: String): String =
        "$title | $text".replace(Regex("\\s+"), " ").replace(Regex("[\\p{L}0-9@._'-]+")) { m ->
            val word = m.value.lowercase(Locale.ROOT)
            when {
                word in keep -> word
                word.any { it.isDigit() } -> "9"
                else -> "x"
            }
        }
}
