//
//  JPViewController.m
//  JSPatch
//
//  Created by bang on 15/5/2.
//  Copyright (c) 2015年 bang. All rights reserved.
//

#import "JPViewController.h"
#import "Masonry.h"

@implementation JPViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    UIButton *btn = [[UIButton alloc] initWithFrame:CGRectMake(10, 100, [UIScreen mainScreen].bounds.size.width - 20, 50)];
    [btn setTitle:@"Push JPTableViewController" forState:UIControlStateNormal];
    [btn addTarget:self action:@selector(handleBtn:) forControlEvents:UIControlEventTouchUpInside];
    [btn setBackgroundColor:[UIColor blueColor]];
    [self.view addSubview:btn];
    
    [btn mas_makeConstraints:^(MASConstraintMaker *make) {
        
    }];
    
    self.view.backgroundColor = [UIColor whiteColor];
}

- (void)handleBtn:(id)sender
{
    NSLog(@"I'am bug");
    [[[UIAlertView alloc] initWithTitle:@"警告" message:@"I'am bug!!!  Please fix!!!" delegate:self cancelButtonTitle:@"确定" otherButtonTitles:nil, nil] show];
}

@end


