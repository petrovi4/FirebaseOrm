//
//  FirebaseOrmConfig.swift
//  FirebaseOrm
//
//  Created by Alexey Talkan on 12/08/2019.
//  Copyright © 2019 Alexey Talkan. All rights reserved.
//

import UIKit
import FirebaseFirestore


open class FirebaseOrmConfig: NSObject {

	static let shared = FirebaseOrmConfig()

	public var db: Firestore


	override init() {
		let settings = FirestoreSettings()
		settings.isPersistenceEnabled = true
		db = Firestore.firestore()
		db.settings = settings
	}
}
