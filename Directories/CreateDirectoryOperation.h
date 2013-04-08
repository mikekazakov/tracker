//
//  CreateDirectoryOperation.h
//  Directories
//
//  Created by Michael G. Kazakov on 08.04.13.
//  Copyright (c) 2013 Michael G. Kazakov. All rights reserved.
//

#import "Operation.h"
#import "OperationDialogAlert.h"

@interface CreateDirectoryOperation : Operation

enum
{
    // Custom dialog results:
    // Skip this and all the following errors.
    CreateDirectoryOperationRetry = OperationDialogResult::Custom
};


- (id)initWithPath:(const char*)_path rootpath:(const char*)_rootpath;

- (OperationDialogAlert *)DialogOnCrDirError:(int)_error
                                   ForDir:(const char *)_path;



@end
