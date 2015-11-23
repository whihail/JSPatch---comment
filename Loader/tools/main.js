defineClass('JPViewController', {
            
    viewDidLoad: function() {

        self.ORIGviewDidLoad();
                
        var label = require('UILabel').alloc().initWithFrame({x:80, y:150, width:200, height:200});
        label.setText("我修改了一个巨大的错误，我能够hotfix，牛逼吧！");
        label.setTextColor(require('UIColor').redColor());
        label.setBackgroundColor(require('UIColor').blueColor());
        self.view().addSubview(label);
    },
            
    handleBtn: function(sender) {
            
        var tableViewCtrl = JPTableViewController.alloc().init()
        self.navigationController().pushViewController_animated(tableViewCtrl, YES)
    }
})

defineClass('JPTableViewController : UITableViewController <UIAlertViewDelegate>', {
  dataSource: function() {
    var data = self.getProp('data')
    if (data) return data;
    var data = [];
    for (var i = 0; i < 20; i ++) {
      data.push("cell from js " + i);
    }
    self.setProp_forKey(data, 'data')
    return data;
  },
  numberOfSectionsInTableView: function(tableView) {
    return 1;
  },
  tableView_numberOfRowsInSection: function(tableView, section) {
    return self.dataSource().count();
  },
  tableView_cellForRowAtIndexPath: function(tableView, indexPath) {
    var cell = tableView.dequeueReusableCellWithIdentifier("cell") 
    if (!cell) {
      cell = require('UITableViewCell').alloc().initWithStyle_reuseIdentifier(0, "cell")
    }
    cell.textLabel().setText(self.dataSource().objectAtIndex(indexPath.row()))
    return cell
  },
  tableView_heightForRowAtIndexPath: function(tableView, indexPath) {
    return 60
  },
  tableView_didSelectRowAtIndexPath: function(tableView, indexPath) {
     var alertView = require('UIAlertView').alloc().initWithTitle_message_delegate_cancelButtonTitle_otherButtonTitles("Alert",self.dataSource().objectAtIndex(indexPath.row()), self, "OK", null);
     alertView.show()
  },
  alertView_willDismissWithButtonIndex: function(alertView, idx) {
    console.log('click btn ' + alertView.buttonTitleAtIndex(idx).toJS())
  }
})