#!/usr/bin/swift
import Foundation

let fileManager = FileManager.default
let currentPath = fileManager.currentDirectoryPath
guard let enumerator = fileManager.enumerator(atPath: currentPath) else {
    print("❌ Erreur : Impossible d'énumérer le répertoire courant.")
    exit(1)
}

let dateFormatter = DateFormatter()
let yearFormatter = DateFormatter()
yearFormatter.dateFormat = "yyyy"
dateFormatter.dateFormat = "yyyy-MM-dd"

print("🛡 Checking Alcyone Sillage source files for dynamic license headers...")

while let filePath = enumerator.nextObject() as? String {
    // Exclusion stricte des dossiers non-sources
    if filePath.hasSuffix(".swift") && !filePath.contains("Pods") && !filePath.contains(".build") && !filePath.contains(".git") {
        let fullPath = URL(fileURLWithPath: currentPath).appendingPathComponent(filePath)
        let fileName = fullPath.lastPathComponent
        
        do {
            let content = try String(contentsOf: fullPath, encoding: .utf8)
            
            // Vérification de la présence de la licence
            if !content.contains("This file is released under the MIT License") {
                print("📝 Adding dynamic header to: \(filePath)")
                
                // Récupération sécurisée de la date de création
                let attributes = try? fileManager.attributesOfItem(atPath: fullPath.path)
                let creationDate = (attributes?[.creationDate] as? Date) ?? Date()
                
                let dateString = dateFormatter.string(from: creationDate)
                let yearString = yearFormatter.string(from: creationDate)
                
                // Génération de l'en-tête (sans saut de ligne final parasite)
                let dynamicHeader = """
                //
                //  \(fileName)
                //  Alcyone Sillage
                //
                //  Created by Alcyone on \(dateString).
                //  Copyright © \(yearString) Alcyone. All rights reserved.
                //  This file is released under the MIT License.
                //  See LICENSE file in the project root for full license information.
                //
                """
                
                // CORRECTION : Insertion explicite d'une ligne vide entre l'en-tête et le code
                let updatedContent = dynamicHeader + "\n\n" + content
                try updatedContent.write(to: fullPath, atomically: true, encoding: .utf8)
            }
        } catch {
            print("⚠️ Error processing \(filePath): \(error.localizedDescription)")
        }
    }
}
print("✅ Audit complete.")
