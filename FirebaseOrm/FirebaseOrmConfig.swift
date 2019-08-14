//
//  FirebaseOrmConfig.swift
//  FirebaseOrm
//
//  Created by Alexey Talkan on 12/08/2019.
//  Copyright © 2019 Alexey Talkan. All rights reserved.
//

import UIKit
import Firebase
import FirebaseFirestore


open class FirebaseOrmConfig: NSObject {

	public static let shared = FirebaseOrmConfig()

	public var db: Firestore
	
	public func configure() {
		FirebaseApp.configure()
	}


	override init() {
		let settings = FirestoreSettings()
		settings.isPersistenceEnabled = true
		db = Firestore.firestore()
		db.settings = settings
	}
}
