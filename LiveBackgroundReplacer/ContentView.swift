//
//  ContentView.swift
//  LiveBackgroundReplacer
//
//  Created by David Arakelyan on 21.08.2024.
//

import SwiftUI

struct ContentView: View {
    var body: some View {
        VStack {
            CameraViewRepresentable()
            CameraButton {
                // Handle camera button tap
                print("Camera button tapped!")
            }
        }
        .padding()
    }
}

#Preview {
    ContentView()
}
