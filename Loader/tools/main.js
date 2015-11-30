
// defineClass(“类名”, {实例方法:jsFunction, 实例方法:jsFunction, ...}, {类方法:jsFunction, 类方法:jsFunction, ...});
defineClass('JPViewController',
    {
        viewDidLoad: function() {

            self.ORIGviewDidLoad();
                    
            var label = require('UILabel').alloc().initWithFrame({x:70, y:170, width:200, height:150});
            label.setText("我修改了一个巨大的错误，我能够hotfix，牛逼吧！");
            label.setNumberOfLines(0);
            label.setTextColor(require('UIColor').redColor());
            label.setBackgroundColor(require('UIColor').blueColor());
            self.view().addSubview(label);
            
            label.mas__makeConstraints(block('MASConstraintMaker*', function(make) {
                                             
                 make.leading().equalTo()(self.view()).offset()(40);
                 make.trailing().equalTo()(self.view()).offset()(-40);
                 make.top().equalTo()(self.view()).offset()(170);
//                 make.height().equalTo()(self.view()).multipliedBy()(0.3);
                 make.height().mas__equalTo()(300);
            }));
        },
                
        handleBtn: function(sender) {
                
            var tableViewCtrl = JPTableViewController.alloc().init()
            self.navigationController().pushViewController_animated(tableViewCtrl, YES)
        }
    },
    {
        load: function() {
            
            self.ORIGload();
        }
            
    }
)

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