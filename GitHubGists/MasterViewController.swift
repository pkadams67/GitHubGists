//
//  MasterViewController.swift
//  GitHubGists
//
//  Created by Paul Kirk Adams on 7/21/16.
//  Copyright © 2016 Paul Kirk Adams. All rights reserved.
//

import UIKit
import PINRemoteImage
import SafariServices
import Alamofire
import BRYXBanner

class MasterViewController: UITableViewController, LoginViewDelegate, SFSafariViewControllerDelegate {
    
    @IBOutlet weak var gistSegmentedControl: UISegmentedControl!
    
    var errorBanner: Banner?
    var detailViewController: DetailViewController? = nil
    var safariViewController: SFSafariViewController?
    var gists = [Gist]()
    var nextPageURLString: String?
    var isLoading = false
    var dateFormatter = NSDateFormatter()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        if let split = self.splitViewController {
            let controllers = split.viewControllers
            self.detailViewController = (controllers[controllers.count-1] as! UINavigationController).topViewController as? DetailViewController
        }
    }
    
    override func viewWillAppear(animated: Bool) {
        self.clearsSelectionOnViewWillAppear = self.splitViewController!.collapsed
        if (self.refreshControl == nil) {
            self.refreshControl = UIRefreshControl()
            self.refreshControl?.addTarget(self, action: #selector(refresh(_:)), forControlEvents: UIControlEvents.ValueChanged)
        }
        self.dateFormatter.dateStyle = .ShortStyle
        self.dateFormatter.timeStyle = .LongStyle
        super.viewWillAppear(animated)
    }
    
    func loadGists(urlToLoad: String?) {
        GitHubAPIManager.sharedInstance.clearCache()
        self.isLoading = true
        let completionHandler: (Result < [Gist], NSError>, String?) -> Void = { (result, nextPage) in
            self.isLoading = false
            self.nextPageURLString = nextPage
            if self.refreshControl != nil && self.refreshControl!.refreshing {
                self.refreshControl?.endRefreshing()
            }
            guard result.error == nil else {
                self.handleLoadGistsError(result.error!)
                return
            }
            guard let fetchedGists = result.value else {
                print("No gists fetched")
                return
            }
            if urlToLoad == nil {
                self.gists = []
            }
            self.gists += fetchedGists
            let path:Path = [.Public, .Starred, .MyGists][self.gistSegmentedControl.selectedSegmentIndex]
            let success = PersistenceManager.saveArray(self.gists, path: path)
            if !success {
                self.showOfflineSaveFailedBanner()
            }
            let now = NSDate()
            let updateString = "Last Updated at " + self.dateFormatter.stringFromDate(now)
            self.refreshControl?.attributedTitle = NSAttributedString(string: updateString)
            self.tableView.reloadData()
        }
        switch gistSegmentedControl.selectedSegmentIndex {
        case 0:
            GitHubAPIManager.sharedInstance.fetchPublicGists(urlToLoad, completionHandler:
                completionHandler)
        case 1:
            GitHubAPIManager.sharedInstance.fetchMyStarredGists(urlToLoad, completionHandler:
                completionHandler)
        case 2:
            GitHubAPIManager.sharedInstance.fetchMyGists(urlToLoad, completionHandler:
                completionHandler)
        default:
            print("Got an unexpected index for selectedSegmentIndex")
        }
    }
    
    func handleLoadGistsError(error: NSError) {
        print(error)
        nextPageURLString = nil
        isLoading = false
        if error.domain != NSURLErrorDomain {
            return
        }
        if error.code == NSURLErrorUserAuthenticationRequired {
            showOAuthLoginView()
        } else if error.code == NSURLErrorNotConnectedToInternet {
            let path:Path = [.Public, .Starred, .MyGists][self.gistSegmentedControl.selectedSegmentIndex]
            if let archived:[Gist] = PersistenceManager.loadArray(path) {
                gists = archived
            } else {
                gists = []
            }
            tableView.reloadData()
            showNotConnectedBanner()
        }
    }
    
    override func viewDidAppear(animated: Bool) {
        super.viewDidAppear(animated)
        if (!GitHubAPIManager.sharedInstance.isLoadingOAuthToken) {
            loadInitialData()
        }
    }
    
    func loadInitialData() {
        isLoading = true
        GitHubAPIManager.sharedInstance.OAuthTokenCompletionHandler = { error in
            guard error == nil else {
                print(error)
                self.isLoading = false
                if error?.domain == NSURLErrorDomain && error?.code == NSURLErrorNotConnectedToInternet {
                    self.showNotConnectedBanner()
                } else {
                    self.showOAuthLoginView()
                }
                return
            }
            if let _ = self.safariViewController {
                self.dismissViewControllerAnimated(false) {}
            }
            self.loadGists(nil)
        }
        
        if (!GitHubAPIManager.sharedInstance.hasOAuthToken()) {
            showOAuthLoginView()
            return
        }
        loadGists(nil)
    }
    
    func showOAuthLoginView() {
        let storyboard = UIStoryboard(name: "Main", bundle: NSBundle.mainBundle())
        GitHubAPIManager.sharedInstance.isLoadingOAuthToken = true
        guard let loginVC = storyboard.instantiateViewControllerWithIdentifier(
            "LoginViewController") as? LoginViewController else {
                assert(false, "Misnamed view controller")
                return
        }
        loginVC.delegate = self
        self.presentViewController(loginVC, animated: true, completion: nil)
    }
    
    func didTapLoginButton() {
        self.dismissViewControllerAnimated(false) {
            guard let authURL = GitHubAPIManager.sharedInstance.URLToStartOAuth2Login() else {
                GitHubAPIManager.sharedInstance.OAuthTokenCompletionHandler?(NSError(domain: GitHubAPIManager.ErrorDomain, code: -1,
                    userInfo: [NSLocalizedDescriptionKey:
                        "Could not create an OAuth authorization URL",
                        NSLocalizedRecoverySuggestionErrorKey: "Please retry your request"]))
                return
            }
            self.safariViewController = SFSafariViewController(URL: authURL)
            self.safariViewController?.delegate = self
            guard let webViewController = self.safariViewController else {
                return
            }
            self.presentViewController(webViewController, animated: true, completion: nil)
        }
    }
    
    func insertNewObject(sender: AnyObject) {
        let createVC = CreateGistViewController(nibName: nil, bundle: nil)
        self.navigationController?.pushViewController(createVC, animated: true)
    }
    
    override func prepareForSegue(segue: UIStoryboardSegue, sender: AnyObject?) {
        if segue.identifier == "showDetail" {
            if let indexPath = self.tableView.indexPathForSelectedRow {
                let gist = gists[indexPath.row] as Gist
                if let detailViewController = (segue.destinationViewController as!
                    UINavigationController).topViewController as?
                    DetailViewController {
                    detailViewController.gist = gist
                    detailViewController.navigationItem.leftBarButtonItem =
                        self.splitViewController?.displayModeButtonItem()
                    detailViewController.navigationItem.leftItemsSupplementBackButton = true
                }
            }
        }
    }
    
    override func numberOfSectionsInTableView(tableView: UITableView) -> Int {
        return 1
    }
    
    override func tableView(tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return gists.count
    }
    
    override func tableView(tableView: UITableView, cellForRowAtIndexPath
        indexPath: NSIndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCellWithIdentifier("Cell", forIndexPath: indexPath)
        let gist = gists[indexPath.row]
        cell.textLabel?.text = gist.gistDescription
        cell.detailTextLabel?.text = gist.ownerLogin
        if let urlString = gist.ownerAvatarURL, url = NSURL(string: urlString) {
            cell.imageView?.pin_setImageFromURL(url, placeholderImage:
                UIImage(named: "placeholder.png"))
        } else {
            cell.imageView?.image = UIImage(named: "placeholder.png")
        }
        if !isLoading {
            let rowsLoaded = gists.count
            let rowsRemaining = rowsLoaded - indexPath.row
            let rowsToLoadFromBottom = 5
            if rowsRemaining <= rowsToLoadFromBottom {
                if let nextPage = nextPageURLString {
                    self.loadGists(nextPage)
                }
            }
        }
        return cell
    }
    
    override func tableView(tableView: UITableView, canEditRowAtIndexPath indexPath:
        NSIndexPath) -> Bool {
        return gistSegmentedControl.selectedSegmentIndex == 2
    }
    
    override func tableView(tableView: UITableView, commitEditingStyle editingStyle:
        UITableViewCellEditingStyle, forRowAtIndexPath indexPath: NSIndexPath) {
        if editingStyle == .Delete {
            let gistToDelete = gists[indexPath.row]
            guard let idToDelete = gistToDelete.id else {
                return
            }
            gists.removeAtIndex(indexPath.row)
            tableView.deleteRowsAtIndexPaths([indexPath], withRowAnimation: .Fade)
            GitHubAPIManager.sharedInstance.deleteGist(idToDelete) {
                (error) in
                if let _ = error {
                    print(error)
                    self.gists.insert(gistToDelete, atIndex: indexPath.row)
                    tableView.insertRowsAtIndexPaths([indexPath], withRowAnimation: .Right)
                    let alertController = UIAlertController(title: "Couldn't delete gist",  message: "Sorry, your gist couldn't be deleted. Maybe GitHub is " + "down or you don't have an Internet connection.", preferredStyle: .Alert)
                    let okAction = UIAlertAction(title: "OK", style: .Default, handler: nil)
                    alertController.addAction(okAction)
                    self.presentViewController(alertController, animated:true, completion: nil)
                }
            }
        } else if editingStyle == .Insert {
        }
    }
    
    func refresh(sender:AnyObject) {
        GitHubAPIManager.sharedInstance.isLoadingOAuthToken = false
        nextPageURLString = nil
        GitHubAPIManager.sharedInstance.clearCache()
        loadInitialData()
    }
    
    func safariViewController(controller: SFSafariViewController, didCompleteInitialLoad
        didLoadSuccessfully: Bool) {
        if (!didLoadSuccessfully) {
            controller.dismissViewControllerAnimated(true, completion: nil)
            GitHubAPIManager.sharedInstance.isAPIOnline { isOnline in
                if !isOnline {
                    print("error: API offline")
                    GitHubAPIManager.sharedInstance.OAuthTokenCompletionHandler?(NSError(domain: NSURLErrorDomain, code:
                        NSURLErrorNotConnectedToInternet,
                        userInfo: [NSLocalizedDescriptionKey: "No Internet connection or GitHub is offline",
                            NSLocalizedRecoverySuggestionErrorKey: "Please retry your request"]))
                }
            }
        }
    }
    
    @IBAction func segmentedControlValueChanged(sender: UISegmentedControl) {
        gists = []
        tableView.reloadData()
        if (gistSegmentedControl.selectedSegmentIndex == 2) {
            self.navigationItem.leftBarButtonItem = self.editButtonItem()
            let addButton = UIBarButtonItem(barButtonSystemItem: .Add, target: self, action: #selector(insertNewObject(_:)))
            self.navigationItem.rightBarButtonItem = addButton
        } else {
            self.navigationItem.leftBarButtonItem = nil
            self.navigationItem.rightBarButtonItem = nil
        }
        loadGists(nil)
    }
    
    func showNotConnectedBanner() {
        if let existingBanner = self.errorBanner {
            existingBanner.dismiss()
        }
        self.errorBanner = Banner(title: "No Internet Connection", subtitle: "Could not load gists." + " Try again when you're connected to the Internet", image: nil, backgroundColor: UIColor.redColor())
        self.errorBanner?.dismissesOnSwipe = true
        self.errorBanner?.show(duration: nil)
    }
    
    func showOfflineSaveFailedBanner() {
        if let existingBanner = self.errorBanner {
            existingBanner.dismiss()
        }
        self.errorBanner = Banner(title: "Could not save gists to view offline", subtitle: "Your iOS device is almost out of free space.\n" +  "You will only be able to see your gists when you have an Internet connection.", image: nil, backgroundColor: UIColor.orangeColor())
        self.errorBanner?.dismissesOnSwipe = true
        self.errorBanner?.show(duration: nil)
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
    }
}