//
//  UIComponents.swift
//  LiveBackgroundReplacer
//
//  Created by David on 02.09.2025.
//

import SwiftUI

struct CameraButton: View {
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Image(systemName: "camera.fill")
                .font(.title2)
                .frame(width: 60, height: 60)
                .background(Color.red)
                .clipShape(Circle())
                .shadow(radius: 5)
        }
        .buttonStyle(PlainButtonStyle())
        
    }
}
