package com.example.myapp

import android.content.ContentProvider
import android.content.ContentValues
import android.database.Cursor
import android.net.Uri

// Exported ContentProvider reachable by any other app via content://authority.
// query() folds caller-supplied `selection` straight into a raw SQL string —
// the classic provider SQL-injection sink the linker should surface from the
// provider handler methods (query/insert/...), not just onCreate.
class ExportedProvider : ContentProvider() {
    override fun onCreate(): Boolean = true

    override fun query(
        uri: Uri,
        projection: Array<String>?,
        selection: String?,
        selectionArgs: Array<String>?,
        sortOrder: String?
    ): Cursor? {
        val db = dbHelper.readableDatabase
        return db.rawQuery("SELECT * FROM items WHERE name = '$selection'", null)
    }

    override fun insert(uri: Uri, values: ContentValues?): Uri? {
        dbHelper.writableDatabase.execSQL("INSERT INTO items VALUES (?)", arrayOf(values))
        return uri
    }
}
