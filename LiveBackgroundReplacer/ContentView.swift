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
            CameraView()
            Image(systemName: "globe")
                .imageScale(.large)
                .foregroundStyle(.tint)
            Text("Live background replacer demo")
        }
        .padding()
    }
}

#Preview {
    ContentView()
}
