//
//  SimpleComboBoxPersistentDataSource.h
//  Files
//
//  Created by Michael G. Kazakov on 15/06/15.
//  Copyright (c) 2015 Michael G. Kazakov. All rights reserved.
//

@interface SimpleComboBoxPersistentDataSource : NSObject<NSComboBoxDataSource>

- (instancetype)initWithPlistPath:(NSString*)path;

- (void)reportEnteredItem:(NSString*)item; // item can be nil

@end