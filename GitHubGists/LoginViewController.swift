//
//  LoginViewController.swift
//  GitHubGists
//
//  Created by Paul Kirk Adams on 7/21/16.
//  Copyright © 2016 Paul Kirk Adams. All rights reserved.
//

import UIKit

protocol LoginViewDelegate: class {
    func didTapLoginButton()
}

class LoginViewController: UIViewController {

    weak var delegate: LoginViewDelegate?
    
    @IBAction func tappedLoginButton() {
        delegate?.didTapLoginButton()
    }
}