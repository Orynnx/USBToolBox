package org.orynnx.hyperusb

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class PrimaryStoragePathResolverTest {
    @Test
    fun acceptsAospAndXiaomiInternalStorageProviders() {
        assertEquals(
            "/storage/emulated/0/Download/disk.img",
            PrimaryStoragePathResolver.resolve(
                "com.android.externalstorage.documents",
                "primary:Download/disk.img",
            ),
        )
        assertEquals(
            "/storage/emulated/0/HyperUSB/disk.img",
            PrimaryStoragePathResolver.resolve(
                "com.android.fileexplorer.documents",
                "primary:HyperUSB/disk.img",
            ),
        )
    }

    @Test
    fun rejectsUntrustedProviderEvenWithPrimaryLookingId() {
        assertNull(
            PrimaryStoragePathResolver.resolve(
                "com.example.cloud.documents",
                "primary:Download/disk.img",
            ),
        )
    }

    @Test
    fun resolvesXiaomiFileProviderExternalFilesPath() {
        assertEquals(
            "/storage/emulated/0/HyperUSB/WePE.iso",
            PrimaryStoragePathResolver.resolveXiaomiFileProvider(
                "com.android.fileexplorer.myprovider",
                listOf("external_files", "HyperUSB", "WePE.iso"),
            ),
        )
        assertNull(
            PrimaryStoragePathResolver.resolveXiaomiFileProvider(
                "com.android.fileexplorer.myprovider",
                listOf("external_files", "..", "private.img"),
            ),
        )
        assertNull(
            PrimaryStoragePathResolver.resolveXiaomiFileProvider(
                "com.example.fileprovider",
                listOf("external_files", "disk.img"),
            ),
        )
    }

    @Test
    fun resolvesTrustedPrimaryDocumentId() {
        assertEquals(
            "/storage/emulated/0/Download/Windows 11.iso",
            PrimaryStoragePathResolver.resolveDocumentId("primary:Download/Windows 11.iso"),
        )
    }

    @Test
    fun rejectsOtherVolumesAndTraversal() {
        assertNull(PrimaryStoragePathResolver.resolveDocumentId("1234-5678:disk.img"))
        assertNull(PrimaryStoragePathResolver.resolveDocumentId("primary:../data/system.img"))
        assertNull(PrimaryStoragePathResolver.resolveDocumentId("primary:"))
        assertNull(PrimaryStoragePathResolver.resolveDocumentId("primary:Download/bad\nname.img"))
    }
}
