//
//  Base.swift
//  FirebaseOrm
//
//  Created by Alexey Talkan on 02/05/2019.
//  Copyright © 2019 Alexey Talkan. All rights reserved.
//

import UIKit
import FirebaseFirestore
//import Bugsnag



/// Every object working with Firebase needs to inherit the base class FBObject and support protocol FBObjectProto
public class FBObject<T>: Hashable where T: FBObjectProto   {
	
	
	/// Return the protocol type - it is necessary to call static methods of the protocol
	/// - Returns: Protocol type
	static func getProtoType() throws -> FBObjectProto.Type {
		guard let selfProtoType = self as? T.Type else {
			throw FirebaseOrmError.notImplementFBObjectProto
		}
		return selfProtoType
	}
	
	
	/// Returns the type that you want to initialize the current QueryDocumentSnapshot
	/// - Returns: Specific type with object constructor
	class func getType(forSnap: QueryDocumentSnapshot) -> FBObjectProto.Type {
		return T.self
	}


	
	/// Typed collection of previously cached objects
	static var cache: [T] {
		get {
			let selfProtoType = self as! FBObjectProto.Type
			return selfProtoType.cacheNonTyped as! [T]
		}
	}

	
	/// Request objects from Firebase
	static func fetch(predicate: NSPredicate? = nil , callback: ((Error?, [T]) -> Void)?)  {
		let callbackWrapper: ((Error?, [T]) -> Void) = {error, items in if let callback = callback { callback(error, items) } }

		guard let protoType = try? self.getProtoType() else {
			callbackWrapper(FirebaseOrmError.notImplementFBObjectProto, [])
			return
		}
		
		var colRef: CollectionReference
		do { colRef = try protoType.getCollRef() }
		catch {
			callbackWrapper(error, [])
			return
		}
		
		let callbackFunc: FIRQuerySnapshotBlock = { (snap, err) in
			if let err = err {
				callbackWrapper(err, [])
				return
			}

			
			let fetchedCollection: [T] = snap!.documents.map {
				let contructType = T.getType(forSnap: $0)
				return contructType.init($0) as! T
			}
			
			var newCollection: [FBObjectProto] = []
			
			// Add all the documents that are not there to the cache
			// If the server has something that is already in the cache - replace the data from the server
			fetchedCollection.forEach({ fetchedItem in
				if let existingIndex = protoType.cacheNonTyped.firstIndex(where: {($0 as! FBObject).documentID == (fetchedItem as! FBObject).documentID}) {
					protoType.cacheNonTyped[existingIndex] = fetchedItem
				}
				else {
					protoType.cacheNonTyped.append(fetchedItem)
					newCollection.append(fetchedItem)
				}
			})
			
			if newCollection.count > 0 { NotificationCenter.default.post(name: protoType.notificationsNames.Added, object: self) }

			callbackWrapper(nil, fetchedCollection)
		}
		
		if let predicate = predicate { colRef.filter(using: predicate).getDocuments(completion: callbackFunc) }
		else { colRef.getDocuments(completion: callbackFunc) }
	}



	/// Save objects from a collection with a single batch query
	static func saveBatch(docs: [FBObject], callback: ((Error?) -> Void)?) {
		let callbackWrapper: ((Error?) -> Void) = {error in if let callback = callback { callback(error) } }

		guard let protoType = try? self.getProtoType() else {
			callbackWrapper(FirebaseOrmError.notImplementFBObjectProto)
			return
		}

		let batch = FirebaseOrmConfig.shared.db.batch()
		docs.forEach { $0.save(batch, callback: nil) }
		batch.commit { error in
			if docs.contains(where: {$0.isNew}) {
				NotificationCenter.default.post(name: protoType.notificationsNames.Added, object: self)
			}
			if docs.contains(where: {!$0.isNew}), let name = protoType.notificationsNames.Edited {
				NotificationCenter.default.post(name: name, object: self)
			}
			callbackWrapper(error)
		}
	}
	
	
	/// Remove objects from a collection with a single batch request
	static func deleteBatch(docs: [FBObject], callback: ((Error?) -> Void)?) {
		let callbackWrapper: ((Error?) -> Void) = {error in if let callback = callback { callback(error) } }

		guard let protoType = try? self.getProtoType() else {
			callbackWrapper(FirebaseOrmError.notImplementFBObjectProto)
			return
		}
		
		let batch = FirebaseOrmConfig.shared.db.batch()
		docs.forEach { $0.delete(batch, callback: nil) }

		batch.commit { error in
			if error == nil && docs.count > 0 {
				let deleteGroup = DispatchGroup()
				docs.forEach { doc in
					deleteGroup.enter()
					doc.deleteComplete { deleteGroup.leave() }
					deleteGroup.notify(queue: DispatchQueue.main) {
						NotificationCenter.default.post(name: protoType.notificationsNames.Removed, object: self)
						callbackWrapper(error)
					}
				}
			}
			else { callbackWrapper(error) }
		}
	}

	
	var documentID: String
	var isNew: Bool
	
	
	init() {
		self.documentID = NSUUID().uuidString
		self.isNew = true
		
		let selfProto = self as! T
		
		let protoType = type(of: selfProto)
		protoType.cacheNonTyped.append(selfProto)
		NotificationCenter.default.post(name: protoType.notificationsNames.Added, object: self)
	}
	
	
	init(_ doc: DocumentSnapshot) {
		self.documentID = doc.documentID
		self.isNew = false
	}

	
	
	/// Overload the method w/o batch and callback
	func save() {
		self.save(nil, callback: nil)
	}
	
	
	/// Overload the method w/o batch
	func save(callback: @escaping ((Error?, T?) -> Void)) {
		self.save(nil, callback: callback)
	}
	
	
	/// Overload the method with batch, but w/o callback
	func save(_ batch: WriteBatch) {
		self.save(batch, callback: nil)
	}
	
	
	/// Saves the object, adds it to the cache if necessary
	/// - Parameter batch: If batch is passed, it only adds to the batch for subsequent commit
	func save(_ batch: WriteBatch?, callback: ((Error?, T?) -> Void)?) {
		let callbackWrapper: ((Error?, T?) -> Void) = {error, item in if let callback = callback { callback(error, item) } }

		guard let selfProto = self as? T else {
			callbackWrapper(FirebaseOrmError.notImplementFBObjectProto, nil)
			return
		}
		let protoType = type(of: selfProto)
		
		let data = selfProto.getData()
		
		var docRef: DocumentReference
		do { docRef = try protoType.getCollRef().document(self.documentID) }
		catch {
			callbackWrapper(error, nil)
			return
		}

		if let batch = batch { batch.setData(data, forDocument: docRef, merge: true) }
		else{
			docRef.setData(data) { error in callbackWrapper(error, selfProto) }
			
			if let name = self.isNew ? protoType.notificationsNames.Added : protoType.notificationsNames.Edited {
				NotificationCenter.default.post(name: name, object: self)
			}
		}
	}

	
	
	/// Overload the method w/o batch and callback
	func delete() {
		self.delete(nil, callback: nil)
	}
	

	/// Deletes the object, cleans it from the cache if necessary
	/// - Parameter batch: If batch is passed, it only adds to the batch for subsequent commit
	func delete(_ batch: WriteBatch?, callback: ((Error?) -> Void)?) {
		let callbackWrapper: ((Error?) -> Void) = {error in if let callback = callback { callback(error) } }

		guard let selfProto = self as? T else {
			callbackWrapper(FirebaseOrmError.notImplementFBObjectProto)
			return
		}
		let protoType = type(of: selfProto)

		var docRef: DocumentReference
		
		do { docRef = try protoType.getCollRef().document(self.documentID) }
		catch {
			callbackWrapper(error)
			return
		}

		// Update cache
		protoType.cacheNonTyped.removeAll(where: {($0 as! FBObject).documentID == self.documentID})

		if let batch = batch { batch.deleteDocument(docRef) }
		else {
			docRef.delete(completion: { (error) in
				if error == nil { self.deleteComplete { callbackWrapper(error) } }
				else { callbackWrapper(error) }
			})
			NotificationCenter.default.post(name: protoType.notificationsNames.Removed, object: self)
		}
	}
	
	
	/// The code block is called when the document is deleted
	/// Can be overloaded in the successor class
	func deleteComplete(callback: @escaping () -> Void) {
		
	}

	
	
	
	// MARK: Hashable
	public static func == (lhs: FBObject, rhs: FBObject) -> Bool {
		return lhs.documentID == rhs.documentID
	}
	
	public func hash(into hasher: inout Hasher) {
		hasher.combine(documentID.hashValue)
	}

}


public protocol FBObjectProto {
	static var cacheNonTyped: [FBObjectProto] { get set }

	init(_ doc: DocumentSnapshot)
	
	static func getCollRef() throws -> CollectionReference
	func getData() -> [String: Any]
	
	
	static var notificationsNames: FBObjectNotifications { get }
	
	/// When creating objects, we will not just take the type T from the generic (this will be the default implementation of this method),
	/// but will give the opportunity to determine what type to create.
	/// This will give the opportunity to inherit FBObject, and then again inherit the heir.
	static func getType(forSnap: QueryDocumentSnapshot) -> FBObjectProto.Type
	
}


public struct FBObjectNotifications {
	let Added: Notification.Name
	let Removed: Notification.Name
	let Edited: Notification.Name?
}
