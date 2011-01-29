//
//  XMLTagSelectionController.h
//  XMLTagInputManager
//
//  Created by Annard Brouwer on 11/01/2005.
//  Copyright 2005 A.H.A. Brouwer. All rights reserved.
//

#import <Cocoa/Cocoa.h>

@interface XMLTagSelectionController: NSObject

+ (void)load;

+ (void)textViewDidChangeSelection: (NSNotification *)notification;

@end

