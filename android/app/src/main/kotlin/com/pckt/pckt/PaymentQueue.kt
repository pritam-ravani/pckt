package com.pckt.pckt

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject
import java.io.File

/**
 * Payments waiting for the app to open and move them into the encrypted
 * database. Entries are removed as soon as Dart has stored them.
 */
object PaymentQueue {
    private const val FILE = "payment_queue.json"
    private const val MAX = 200

    private fun file(context: Context) = File(context.noBackupFilesDir, FILE)

    private fun read(context: Context): JSONArray = try {
        JSONArray(file(context).readText())
    } catch (e: Exception) {
        JSONArray()
    }

    private fun write(context: Context, items: JSONArray) {
        val target = file(context)
        val temp = File(target.parentFile, "$FILE.tmp")
        temp.writeText(items.toString())
        temp.renameTo(target)
    }

    private fun JSONArray.objects() = (0 until length()).map { getJSONObject(it) }

    @Synchronized
    fun add(context: Context, entry: JSONObject) {
        val items = read(context).objects().takeLast(MAX - 1) + entry
        write(context, JSONArray(items))
    }

    /** Records the user's pick. If the app already took the payment, a stub carries the pick over. */
    @Synchronized
    fun choose(context: Context, id: String, category: String) {
        val items = read(context).objects()
        val found = items.firstOrNull { it.optString("id") == id }
        if (found != null) {
            found.put("category", category)
            write(context, JSONArray(items))
        } else {
            write(context, JSONArray(items + JSONObject().put("id", id).put("category", category).put("choiceOnly", true)))
        }
    }

    /** Payments still waiting for a category, for the check-in reminder. */
    @Synchronized
    fun waitingCount(context: Context): Int =
        read(context).objects().count { !it.optBoolean("choiceOnly") && it.isNull("category") }

    @Synchronized
    fun all(context: Context): String = read(context).toString()

    @Synchronized
    fun remove(context: Context, ids: Set<String>) {
        write(context, JSONArray(read(context).objects().filter { it.optString("id") !in ids }))
    }
}
