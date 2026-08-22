package org.orynnx.hyperusb

internal object PrimaryStoragePathResolver {
    private val trustedAuthorities = setOf(
        "com.android.externalstorage.documents",
        "com.android.fileexplorer.documents",
    )

    fun resolve(authority: String?, documentId: String): String? {
        if (authority !in trustedAuthorities) return null
        return resolveDocumentId(documentId)
    }

    fun resolveXiaomiFileProvider(authority: String?, pathSegments: List<String>): String? {
        if (authority != "com.android.fileexplorer.myprovider" ||
            pathSegments.firstOrNull() != "external_files"
        ) return null
        return resolveRelativePath(pathSegments.drop(1))
    }

    fun resolveDocumentId(documentId: String): String? {
        if (!documentId.startsWith("primary:")) return null
        val relative = documentId.removePrefix("primary:").trim('/')
        return resolveRelativePath(relative.split('/'))
    }

    private fun resolveRelativePath(segments: List<String>): String? {
        if (segments.isEmpty() || segments.any { segment ->
                segment.isEmpty() || segment == "." || segment == ".." ||
                    segment.any { it == '\u0000' || it == '\r' || it == '\n' }
            }
        ) return null
        return "/storage/emulated/0/${segments.joinToString("/")}"
    }
}
