import CoreData
import Foundation

@MainActor
final class TextSyncLocalStore {
    static let defaultAppTitle = "RelayClip"

    private let container: NSPersistentContainer

    init() {
        let model = NSManagedObjectModel()
        let entryEntity = NSEntityDescription()
        entryEntity.name = "CachedEntry"
        entryEntity.managedObjectClassName = NSStringFromClass(NSManagedObject.self)

        let id = NSAttributeDescription()
        id.name = "id"
        id.attributeType = .integer64AttributeType
        id.isOptional = false

        let time = NSAttributeDescription()
        time.name = "time"
        time.attributeType = .dateAttributeType
        time.isOptional = false

        let content = NSAttributeDescription()
        content.name = "content"
        content.attributeType = .stringAttributeType
        content.isOptional = false

        let kind = NSAttributeDescription()
        kind.name = "kind"
        kind.attributeType = .stringAttributeType
        kind.isOptional = true

        let category = NSAttributeDescription()
        category.name = "category"
        category.attributeType = .stringAttributeType
        category.isOptional = true

        let mimeType = NSAttributeDescription()
        mimeType.name = "mimeType"
        mimeType.attributeType = .stringAttributeType
        mimeType.isOptional = true

        let assetURL = NSAttributeDescription()
        assetURL.name = "assetURL"
        assetURL.attributeType = .stringAttributeType
        assetURL.isOptional = true

        let thumbnailURL = NSAttributeDescription()
        thumbnailURL.name = "thumbnailURL"
        thumbnailURL.attributeType = .stringAttributeType
        thumbnailURL.isOptional = true

        let fileName = NSAttributeDescription()
        fileName.name = "fileName"
        fileName.attributeType = .stringAttributeType
        fileName.isOptional = true

        let width = NSAttributeDescription()
        width.name = "width"
        width.attributeType = .integer64AttributeType
        width.isOptional = true

        let height = NSAttributeDescription()
        height.name = "height"
        height.attributeType = .integer64AttributeType
        height.isOptional = true

        let byteCount = NSAttributeDescription()
        byteCount.name = "byteCount"
        byteCount.attributeType = .integer64AttributeType
        byteCount.isOptional = true

        let serverDeletedAt = NSAttributeDescription()
        serverDeletedAt.name = "serverDeletedAt"
        serverDeletedAt.attributeType = .dateAttributeType
        serverDeletedAt.isOptional = true

        let serverAddress = NSAttributeDescription()
        serverAddress.name = "serverAddress"
        serverAddress.attributeType = .stringAttributeType
        serverAddress.isOptional = true

        let isDeleted = NSAttributeDescription()
        isDeleted.name = "isDeleted"
        isDeleted.attributeType = .booleanAttributeType
        isDeleted.isOptional = false
        isDeleted.defaultValue = false

        let isPinned = NSAttributeDescription()
        isPinned.name = "isPinned"
        isPinned.attributeType = .booleanAttributeType
        isPinned.isOptional = false
        isPinned.defaultValue = false

        let isLocallyEdited = NSAttributeDescription()
        isLocallyEdited.name = "isLocallyEdited"
        isLocallyEdited.attributeType = .booleanAttributeType
        isLocallyEdited.isOptional = false
        isLocallyEdited.defaultValue = false

        let isLocalOnly = NSAttributeDescription()
        isLocalOnly.name = "isLocalOnly"
        isLocalOnly.attributeType = .booleanAttributeType
        isLocalOnly.isOptional = false
        isLocalOnly.defaultValue = false

        entryEntity.properties = [
            id,
            time,
            content,
            kind,
            category,
            mimeType,
            assetURL,
            thumbnailURL,
            fileName,
            width,
            height,
            byteCount,
            serverDeletedAt,
            serverAddress,
            isDeleted,
            isPinned,
            isLocallyEdited,
            isLocalOnly
        ]

        let settingEntity = NSEntityDescription()
        settingEntity.name = "AppSetting"
        settingEntity.managedObjectClassName = NSStringFromClass(NSManagedObject.self)

        let key = NSAttributeDescription()
        key.name = "key"
        key.attributeType = .stringAttributeType
        key.isOptional = false

        let value = NSAttributeDescription()
        value.name = "value"
        value.attributeType = .stringAttributeType
        value.isOptional = false

        settingEntity.properties = [key, value]
        model.entities = [entryEntity, settingEntity]

        container = NSPersistentContainer(name: "TextSyncLocalStore", managedObjectModel: model)
        let description = container.persistentStoreDescriptions.first
        description?.shouldMigrateStoreAutomatically = true
        description?.shouldInferMappingModelAutomatically = true
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy

        var loadError: Error?
        let semaphore = DispatchSemaphore(value: 0)
        container.loadPersistentStores { _, error in
            loadError = error
            semaphore.signal()
        }
        semaphore.wait()

        if let loadError {
            assertionFailure("Core Data store failed to load: \(loadError)")
        }
    }

    func visibleEntries(serverAddress: String) throws -> [SyncEntry] {
        try entries(serverAddress: serverAddress, includeHidden: false)
    }

    func hiddenEntries(serverAddress: String) throws -> [SyncEntry] {
        let request = NSFetchRequest<NSManagedObject>(entityName: "CachedEntry")
        let serverKey = cacheServerKey(serverAddress)
        if serverKey.isEmpty {
            request.predicate = NSPredicate(format: "isDeleted == YES AND serverDeletedAt == nil")
        } else {
            request.predicate = NSPredicate(format: "isDeleted == YES AND serverDeletedAt == nil AND (serverAddress == %@ OR serverAddress == nil)", serverKey)
        }
        request.sortDescriptors = [NSSortDescriptor(key: "id", ascending: true)]
        return try container.viewContext.fetch(request).compactMap(makeEntry)
    }

    func trashEntries(serverAddress: String) throws -> [SyncEntry] {
        let request = NSFetchRequest<NSManagedObject>(entityName: "CachedEntry")
        let serverKey = cacheServerKey(serverAddress)
        if serverKey.isEmpty {
            request.predicate = NSPredicate(format: "serverDeletedAt != nil")
        } else {
            request.predicate = NSPredicate(format: "serverDeletedAt != nil AND (serverAddress == %@ OR serverAddress == nil)", serverKey)
        }
        request.sortDescriptors = [NSSortDescriptor(key: "id", ascending: false)]
        return try container.viewContext.fetch(request).compactMap(makeEntry)
    }

    func merge(_ remoteEntries: [SyncEntry], serverAddress: String, preserveLocalEdits: Bool) throws {
        let serverKey = cacheServerKey(serverAddress)
        for entry in remoteEntries {
            let object = try cachedObject(id: entry.id, serverAddress: serverKey) ?? NSEntityDescription.insertNewObject(forEntityName: "CachedEntry", into: container.viewContext)
            let shouldKeepLocalContent = preserveLocalEdits && (object.value(forKey: "isLocallyEdited") as? Bool ?? false)
            object.setValue(Int64(entry.id), forKey: "id")
            if !shouldKeepLocalContent {
                object.setValue(entry.time, forKey: "time")
                object.setValue(entry.content, forKey: "content")
                object.setValue(false, forKey: "isLocallyEdited")
            }
            updateMetadata(on: object, with: entry)
            object.setValue(serverKey, forKey: "serverAddress")
            object.setValue(false, forKey: "isLocalOnly")
            if object.value(forKey: "isDeleted") == nil {
                object.setValue(false, forKey: "isDeleted")
            }
            if object.value(forKey: "isPinned") == nil {
                object.setValue(false, forKey: "isPinned")
            }
            if object.value(forKey: "isLocallyEdited") == nil {
                object.setValue(false, forKey: "isLocallyEdited")
            }
            if object.value(forKey: "isLocalOnly") == nil {
                object.setValue(false, forKey: "isLocalOnly")
            }
        }
        try saveIfNeeded()
    }

    func markHidden(id: Int, serverAddress: String, isHidden: Bool) throws {
        guard let object = try cachedObject(id: id, serverAddress: cacheServerKey(serverAddress)) else { return }
        object.setValue(isHidden, forKey: "isDeleted")
        try saveIfNeeded()
    }

    func restoreHiddenEntries(ids: [Int], serverAddress: String) throws {
        for id in ids {
            try markHidden(id: id, serverAddress: serverAddress, isHidden: false)
        }
    }

    func resetCachedEntries(serverAddress: String) throws {
        let request = NSFetchRequest<NSManagedObject>(entityName: "CachedEntry")
        let serverKey = cacheServerKey(serverAddress)
        if !serverKey.isEmpty {
            request.predicate = NSPredicate(format: "serverAddress == %@ OR serverAddress == nil", serverKey)
        }

        let objects = try container.viewContext.fetch(request)
        for object in objects {
            container.viewContext.delete(object)
        }
        try saveIfNeeded()
    }

    func markPinned(id: Int, serverAddress: String, isPinned: Bool) throws {
        guard let object = try cachedObject(id: id, serverAddress: cacheServerKey(serverAddress)) else { return }
        object.setValue(isPinned, forKey: "isPinned")
        try saveIfNeeded()
    }

    func saveLocalContent(id: Int, serverAddress: String, content: String) throws {
        guard let object = try cachedObject(id: id, serverAddress: cacheServerKey(serverAddress)) else { return }
        object.setValue(content, forKey: "content")
        object.setValue(true, forKey: "isLocallyEdited")
        try saveIfNeeded()
    }

    func replaceWithRemote(_ entry: SyncEntry, serverAddress: String) throws {
        let serverKey = cacheServerKey(serverAddress)
        let object = try cachedObject(id: entry.id, serverAddress: serverKey) ?? NSEntityDescription.insertNewObject(forEntityName: "CachedEntry", into: container.viewContext)
        object.setValue(Int64(entry.id), forKey: "id")
        object.setValue(entry.time, forKey: "time")
        object.setValue(entry.content, forKey: "content")
        updateMetadata(on: object, with: entry)
        object.setValue(false, forKey: "isLocallyEdited")
        object.setValue(false, forKey: "isLocalOnly")
        object.setValue(serverKey, forKey: "serverAddress")
        if object.value(forKey: "isDeleted") == nil {
            object.setValue(false, forKey: "isDeleted")
        }
        if object.value(forKey: "isPinned") == nil {
            object.setValue(false, forKey: "isPinned")
        }
        try saveIfNeeded()
    }

    func createLocalTextEntry(content: String, serverAddress: String) throws -> SyncEntry {
        try createLocalEntry(
            content: content,
            kind: "text",
            category: DetectedContentAction.primaryCategory(kind: "text", content: content),
            mimeType: nil,
            assetURL: nil,
            thumbnailURL: nil,
            fileName: nil,
            width: nil,
            height: nil,
            byteCount: nil,
            serverAddress: serverAddress
        )
    }

    func createLocalImageEntry(payload: ClipboardImagePayload, serverAddress: String) throws -> SyncEntry {
        let entry = try createLocalEntry(
            content: "图片 \(payload.fileName)",
            kind: "image",
            category: "image",
            mimeType: payload.mimeType,
            assetURL: "textsync-local-image://\(UUID().uuidString)",
            thumbnailURL: nil,
            fileName: payload.fileName,
            width: nil,
            height: nil,
            byteCount: payload.data.count,
            serverAddress: serverAddress
        )
        try? ImageDiskCache.store(payload.data, for: entry, serverAddress: serverAddress, variant: "asset")
        try? ImageDiskCache.store(payload.data, for: entry, serverAddress: serverAddress, variant: "thumb")
        ImageDiskCache.prune()
        return entry
    }

    func deleteLocalEntry(_ entry: SyncEntry, serverAddress: String) throws {
        guard let object = try cachedObject(id: entry.id, serverAddress: cacheServerKey(serverAddress)) else { return }
        container.viewContext.delete(object)
        try saveIfNeeded()
    }

    func serverAddress() throws -> String {
        try settingValue(forKey: "serverAddress")
    }

    func appTitle() throws -> String {
        let title = try settingValue(forKey: "appTitle").trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? Self.defaultAppTitle : title
    }

    func automaticRemoteUploadEnabled() throws -> Bool {
        try settingValue(forKey: "automaticRemoteUploadEnabled") == "1"
    }

    func hotKeyShortcut() throws -> HotKeyShortcut {
        let value = try settingValue(forKey: "hotKeyPreset")
        return HotKeyShortcut(storageValue: value)
    }

    func quickPanelPlacement() throws -> QuickPanelPlacement {
        let value = try settingValue(forKey: "quickPanelPlacement")
        return QuickPanelPlacement(rawValue: value) ?? .mouse
    }

    func saveServerAddress(_ address: String) throws {
        try saveSetting(key: "serverAddress", value: address.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    func saveAppTitle(_ title: String) throws {
        let value = title.trimmingCharacters(in: .whitespacesAndNewlines)
        try saveSetting(key: "appTitle", value: value.isEmpty ? Self.defaultAppTitle : value)
    }

    func saveAutomaticRemoteUploadEnabled(_ isEnabled: Bool) throws {
        try saveSetting(key: "automaticRemoteUploadEnabled", value: isEnabled ? "1" : "0")
    }

    func saveHotKeyShortcut(_ shortcut: HotKeyShortcut) throws {
        try saveSetting(key: "hotKeyPreset", value: shortcut.storageValue)
    }

    func saveQuickPanelPlacement(_ placement: QuickPanelPlacement) throws {
        try saveSetting(key: "quickPanelPlacement", value: placement.rawValue)
    }

    private func entries(serverAddress: String, includeHidden: Bool) throws -> [SyncEntry] {
        let request = NSFetchRequest<NSManagedObject>(entityName: "CachedEntry")
        let serverKey = cacheServerKey(serverAddress)
        if serverKey.isEmpty {
            request.predicate = includeHidden
                ? NSPredicate(format: "serverDeletedAt == nil")
                : NSPredicate(format: "isDeleted == NO AND serverDeletedAt == nil")
        } else {
            request.predicate = includeHidden
                ? NSPredicate(format: "serverDeletedAt == nil AND (serverAddress == %@ OR serverAddress == nil)", serverKey)
                : NSPredicate(format: "isDeleted == NO AND serverDeletedAt == nil AND (serverAddress == %@ OR serverAddress == nil)", serverKey)
        }
        request.sortDescriptors = [
            NSSortDescriptor(key: "time", ascending: true),
            NSSortDescriptor(key: "id", ascending: true)
        ]
        return try container.viewContext.fetch(request).compactMap(makeEntry)
    }

    private func createLocalEntry(
        content: String,
        kind: String,
        category: String,
        mimeType: String?,
        assetURL: String?,
        thumbnailURL: String?,
        fileName: String?,
        width: Int?,
        height: Int?,
        byteCount: Int?,
        serverAddress: String
    ) throws -> SyncEntry {
        let object = NSEntityDescription.insertNewObject(forEntityName: "CachedEntry", into: container.viewContext)
        let entry = SyncEntry(
            id: try nextLocalID(),
            time: Date(),
            content: content,
            kind: kind,
            category: category,
            mimeType: mimeType,
            assetURL: assetURL,
            thumbnailURL: thumbnailURL,
            fileName: fileName,
            width: width,
            height: height,
            byteCount: byteCount,
            isLocalOnly: true
        )

        object.setValue(Int64(entry.id), forKey: "id")
        object.setValue(entry.time, forKey: "time")
        object.setValue(entry.content, forKey: "content")
        updateMetadata(on: object, with: entry)
        object.setValue(nil, forKey: "serverAddress")
        object.setValue(false, forKey: "isDeleted")
        object.setValue(false, forKey: "isPinned")
        object.setValue(false, forKey: "isLocallyEdited")
        object.setValue(true, forKey: "isLocalOnly")
        try saveIfNeeded()
        return entry
    }

    private func nextLocalID() throws -> Int {
        let request = NSFetchRequest<NSManagedObject>(entityName: "CachedEntry")
        request.sortDescriptors = [NSSortDescriptor(key: "id", ascending: true)]
        request.fetchLimit = 1
        let lowestID = try container.viewContext.fetch(request).first?.value(forKey: "id") as? Int64 ?? 0
        return lowestID < 0 ? Int(lowestID - 1) : -1
    }

    private func saveSetting(key: String, value: String) throws {
        let object = try settingObject(key: key) ?? NSEntityDescription.insertNewObject(forEntityName: "AppSetting", into: container.viewContext)
        object.setValue(key, forKey: "key")
        object.setValue(value, forKey: "value")
        try saveIfNeeded()
    }

    private func cachedObject(id: Int, serverAddress: String) throws -> NSManagedObject? {
        let request = NSFetchRequest<NSManagedObject>(entityName: "CachedEntry")
        if serverAddress.isEmpty {
            request.predicate = NSPredicate(format: "id == %lld", Int64(id))
        } else {
            request.predicate = NSPredicate(format: "id == %lld AND (serverAddress == %@ OR serverAddress == nil)", Int64(id), serverAddress)
        }
        request.fetchLimit = 1
        return try container.viewContext.fetch(request).first
    }

    private func cacheServerKey(_ address: String) -> String {
        if let normalized = try? ServerAddress.normalized(address) {
            return normalized
        }
        return address.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func settingValue(forKey key: String) throws -> String {
        guard let object = try settingObject(key: key) else { return "" }
        return object.value(forKey: "value") as? String ?? ""
    }

    private func settingObject(key: String) throws -> NSManagedObject? {
        let request = NSFetchRequest<NSManagedObject>(entityName: "AppSetting")
        request.predicate = NSPredicate(format: "key == %@", key)
        request.fetchLimit = 1
        return try container.viewContext.fetch(request).first
    }

    private func makeEntry(from object: NSManagedObject) -> SyncEntry? {
        guard let time = object.value(forKey: "time") as? Date,
              let content = object.value(forKey: "content") as? String else {
            return nil
        }
        let id = object.value(forKey: "id") as? Int64 ?? 0
        let isPinned = object.value(forKey: "isPinned") as? Bool ?? false
        let isLocallyEdited = object.value(forKey: "isLocallyEdited") as? Bool ?? false
        let isLocalOnly = object.value(forKey: "isLocalOnly") as? Bool ?? false
        let isHidden = object.value(forKey: "isDeleted") as? Bool ?? false
        return SyncEntry(
            id: Int(id),
            time: time,
            content: content,
            kind: object.value(forKey: "kind") as? String ?? "text",
            category: object.value(forKey: "category") as? String ?? "",
            mimeType: object.value(forKey: "mimeType") as? String,
            assetURL: object.value(forKey: "assetURL") as? String,
            thumbnailURL: object.value(forKey: "thumbnailURL") as? String,
            fileName: object.value(forKey: "fileName") as? String,
            width: (object.value(forKey: "width") as? Int64).map { Int($0) },
            height: (object.value(forKey: "height") as? Int64).map { Int($0) },
            byteCount: (object.value(forKey: "byteCount") as? Int64).map { Int($0) },
            deletedAt: object.value(forKey: "serverDeletedAt") as? Date,
            isPinned: isPinned,
            isLocallyEdited: isLocallyEdited,
            isLocalOnly: isLocalOnly,
            isHidden: isHidden
        )
    }

    private func updateMetadata(on object: NSManagedObject, with entry: SyncEntry) {
        object.setValue(entry.kind, forKey: "kind")
        object.setValue(entry.category, forKey: "category")
        object.setValue(entry.mimeType, forKey: "mimeType")
        object.setValue(entry.assetURL, forKey: "assetURL")
        object.setValue(entry.thumbnailURL, forKey: "thumbnailURL")
        object.setValue(entry.fileName, forKey: "fileName")
        object.setValue(entry.width.map { Int64($0) }, forKey: "width")
        object.setValue(entry.height.map { Int64($0) }, forKey: "height")
        object.setValue(entry.byteCount.map { Int64($0) }, forKey: "byteCount")
        object.setValue(entry.deletedAt, forKey: "serverDeletedAt")
    }

    private func saveIfNeeded() throws {
        if container.viewContext.hasChanges {
            try container.viewContext.save()
        }
    }
}
