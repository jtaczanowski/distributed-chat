//
//  ProfileView.swift
//  DistributedChatApp
//
//  Created by Fredrik on 1/23/21.
//

import SwiftUI

struct ProfileView: View {
    @EnvironmentObject private var profile: Profile
    
    var body: some View {
        NavigationView {
            VStack(alignment: .center, spacing: 40) {
                Image(systemName: "person.circle")
                    .resizable()
                    .frame(width: 80, height: 80, alignment: .center)
                TextField("Your nickname", text: $profile.presence.user.name)
                    .font(.title2)
                    .multilineTextAlignment(.center)
            }
            .padding(20)
            .navigationTitle("Profile")
        }
    }
}

struct ProfileView_Previews: PreviewProvider {
    @StateObject static var profile = Profile()
    static var previews: some View {
        ProfileView()
            .environmentObject(profile)
    }
}
