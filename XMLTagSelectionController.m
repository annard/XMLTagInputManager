//
//  XMLTagSelectionController.m
//  XMLTagInputManager
//
//  Created by Annard Brouwer on 11/01/2005.
//  Copyright 2005 A.H.A. Brouwer. All rights reserved.
//

#import "XMLTagSelectionController.h"

#define OPEN_TAG_ELEMENT_CHAR  '<'
#define CLOSE_TAG_ELEMENT_CHAR '>'
#define BUFF_SIZE              512
#define MIN_TAG_ELEMENT_LENGTH 3

typedef enum XMLTagTypes
{
    InvalidTagType = 0,
    OpenTagType,
    CloseTagType,
    SelfCloseTagType,
    CommentTagType,
    DefinitionTagType
} XMLTagTypes;

unichar tagDelimiterCharSelectedInString(NSRange *selRange, NSString *string);

NSRange selectedTagRangeInString(unichar c, NSRange origRange, NSString *string);

NSRange extendedMatchRangeWithOpenTagInString(NSRange matchRange, NSString *string);
NSRange extendedMatchRangeWithCloseTagInString(NSRange matchRange, NSString *string);

XMLTagTypes tagTypeOfString(NSString *string);

@implementation XMLTagSelectionController

+ (void)load
{
    [[NSNotificationCenter defaultCenter] addObserver: self
                                             selector: @selector(textViewDidChangeSelection:)
                                                 name: NSTextViewDidChangeSelectionNotification
                                               object: nil];
    //NSLog(@"[XMLTagInputManager] Registered XMLTagSelectionController");
}

+ (void)textViewDidChangeSelection: (NSNotification *)notification
{
    if ([[NSApp currentEvent] type] == NSLeftMouseUp)
    {
        NSTextView *textView;
        NSRange selRange;
        int clickCount;
        
        textView = [notification object];
        selRange.location = [textView selectedRange].location;
        selRange.length = [textView selectedRange].length;
        
        clickCount = [[NSApp currentEvent] clickCount];
        if (2 == clickCount)
        {
            // Select tag if clicked inside a tag element
            unichar c;
            NSRange matchRange;
            
            // Is the selection inside a tag?
            c = tagDelimiterCharSelectedInString(&selRange, [textView string]);
            if (0 == c)
                return;
            
            matchRange = selectedTagRangeInString(c, selRange, [textView string]);
            
            if (matchRange.location != NSNotFound)
            {
                // Is valid XML tag?
                if (InvalidTagType != tagTypeOfString([[textView string] substringWithRange: matchRange]))
                {
                    [textView setSelectedRange: matchRange
                                      affinity: NSSelectionAffinityDownstream
                                stillSelecting: YES];
                    [textView scrollRangeToVisible: matchRange];
                }
            }
        }
        else if (3 == clickCount)
        {
            // if clicked inside a tag element, select everything from start tag incl. end tag
            unichar c;
            NSRange oldSelRange, matchRange;
            
            // Use the old selected range
            oldSelRange = [[[notification userInfo] objectForKey: @"NSOldSelectedCharacterRange"] rangeValue];
            selRange.location = oldSelRange.location;
            selRange.length = oldSelRange.length;
            // Is the selection inside a tag?
            c = tagDelimiterCharSelectedInString(&selRange, [textView string]);
            if (0 == c)
                return;
            
            matchRange = selectedTagRangeInString(c, selRange, [textView string]);
            
            if (matchRange.location != NSNotFound)
            {
                XMLTagTypes tagType;
                
                // Is valid XML tag?
                tagType = tagTypeOfString([[textView string] substringWithRange: matchRange]);
                switch (tagType)
                {
                    case OpenTagType:
                        matchRange = extendedMatchRangeWithCloseTagInString(matchRange, [textView string]);
                        break;
                    case CloseTagType:
                        matchRange = extendedMatchRangeWithOpenTagInString(matchRange, [textView string]);
                        break;
                    case SelfCloseTagType:
                    case CommentTagType:
                    case DefinitionTagType:
                    case InvalidTagType:
                    default:
                        return; // "Normal behaviour"
                }
                if (NSNotFound == matchRange.location)
                    return;
                
                [textView setSelectedRange: matchRange
                                  affinity: NSSelectionAffinityDownstream
                            stillSelecting: YES];
                [textView scrollRangeToVisible: selRange];
            }                    
        }
    }
}

// Utility functions

// Returns YES if selRange starts with '<' or '>' (or contains ".><."),
// otherwise returns 0
unichar tagDelimiterCharSelectedInString(NSRange *selRange, NSString *string)
{
    int strLen, idx, maxIdx, testIdx;
    unichar c;
    NSCharacterSet *ws;

    strLen = [string length];
    if ((NSNotFound == selRange->location) || (0 == selRange->length) || 0 == strLen)
        return (unichar)0;

    idx = selRange->location;
    maxIdx = idx + selRange->length;
    ws = [NSCharacterSet whitespaceAndNewlineCharacterSet];
    @try
    {
        while ((idx <= maxIdx) && (idx < strLen))
        {
            c = [string characterAtIndex: idx];
            if (! [ws characterIsMember: c])
                break;
            idx++;
        }
        selRange->length -= (idx - selRange->location);
        selRange->location = idx;
        if (OPEN_TAG_ELEMENT_CHAR == c)
            return c;

        testIdx = NSMaxRange(*selRange) - 1;
        if ((testIdx >= 0) && (testIdx < strLen))
        {
            c = [string characterAtIndex: testIdx];
            if (CLOSE_TAG_ELEMENT_CHAR == c)
                return c;
        }
        // Special case for "...><...", we'll imagine there is a space in between
        // and return "<..."
        while (idx >= 0 && idx < maxIdx)
        {
            c = [string characterAtIndex: idx];
            if (CLOSE_TAG_ELEMENT_CHAR == c
                && [string characterAtIndex: idx + 1] == OPEN_TAG_ELEMENT_CHAR)
            {
                selRange->length -= (idx + 1 - selRange->location);
                selRange->location = idx + 1;
                return OPEN_TAG_ELEMENT_CHAR;
            }
            idx++;
        }
    }
    @catch (NSException *nse)
    {
        NSLog(@"[XMLTagInputManager] Error while trying to detect tags for range [%d, %d] in string \"%@\"[%d]: %@", selRange->location, selRange->length, string, strLen, nse);
    }
    return (unichar)0;
}

// Returns a range that defines the tag wherein the user has clicked that defines
// the tag. If the first tag element delimiter encountered to the left of the
// current selection is '>' or none, give up and return an empty range.
// Otherwise, if '<' is encountered to the left, search for a closing '>' to
// the right of the start location and return the range that encompasses these
// delimiters. If none is found return an empty range.
NSRange selectedTagRangeInString(unichar c, NSRange origRange, NSString *string)
{
    NSRange matchRange;
    
    matchRange = NSMakeRange(NSNotFound, 0);
    if (CLOSE_TAG_ELEMENT_CHAR == c)
    {
        // Search to for '<'
        NSRange searchRange;
        bool done;

        searchRange = NSMakeRange(0, origRange.location - 1);
        done = NO;
        while ((searchRange.length > 0) && !done)
        {
            NSRange buffRange;
            unichar buff[BUFF_SIZE];
            int i;
            
            // Fill the buffer with a chunk of the searchRange
            if (searchRange.length <= BUFF_SIZE)
            {
                buffRange = searchRange;
            }
            else
            {
                buffRange = NSMakeRange(NSMaxRange(searchRange) - BUFF_SIZE, BUFF_SIZE);
            }
            [string getCharacters: buff range: buffRange];
            
            // This loops over all the characters in buffRange.
            for (i = buffRange.length - 1; i >= 0; i--)
            {
                if (CLOSE_TAG_ELEMENT_CHAR == buff[i])
                {
                    done = YES;
                    break;
                }
                else if (OPEN_TAG_ELEMENT_CHAR == buff[i])
                {
                    done = YES;
                    matchRange = NSMakeRange(buffRange.location + i,
                                             origRange.location - buffRange.location - i + origRange.length);
                    break;
                }
            }
            
            // Remove the buffRange from the searchRange.
            searchRange.length -= buffRange.length;
        }
    }
    else if (OPEN_TAG_ELEMENT_CHAR == c)
    {
        // Search for '>'
        NSRange searchRange;
        bool done;
        
        searchRange = NSMakeRange(origRange.location + 1,
                                  [string length] - (origRange.location + 1));
        done = NO;
        while ((searchRange.length > 0) && !done)
        {
            NSRange buffRange;
            unichar buff[BUFF_SIZE];
            int i;
            
            // Fill the buffer with a chunk of the searchRange
            if (searchRange.length <= BUFF_SIZE)
            {
                buffRange = searchRange;
            }
            else
            {
                buffRange = NSMakeRange(searchRange.location, BUFF_SIZE);
            }
            [string getCharacters: buff range: buffRange];
            
            // This loops over all the characters in buffRange.
            for (i = 0; i < buffRange.length; i++)
            {
                if (OPEN_TAG_ELEMENT_CHAR == buff[i])
                {
                    matchRange.location = NSNotFound;
                    done = YES;
                    break;
                }
                else if (CLOSE_TAG_ELEMENT_CHAR == buff[i])
                {
                    done = YES;
                    matchRange = NSMakeRange(origRange.location,
                                             searchRange.location + i + 1 - origRange.location);
                    break;
                }
            }
            searchRange.location += buffRange.length;
            // Remove the buffRange from the searchRange.
            searchRange.length -= buffRange.length;
        }
    }
    return matchRange;
}

// Returns the type of the tag in the string.
XMLTagTypes tagTypeOfString(NSString *string)
{
    unichar c;
    bool hasClosingChar;
    
    if ([string length] < MIN_TAG_ELEMENT_LENGTH)
        return InvalidTagType;
    c = [string characterAtIndex: [string length] - 1];
    if (CLOSE_TAG_ELEMENT_CHAR != c)
        return InvalidTagType;
    
    c = [string characterAtIndex: 0];
    if (OPEN_TAG_ELEMENT_CHAR == c)
    {
        c = [string characterAtIndex: 1];
        if ('!' == c)
            return CommentTagType;
        else if ('?' == c)
            return DefinitionTagType;
        else if ('/' == c)
            return CloseTagType;
        else if (CFCharacterSetIsCharacterMember(CFCharacterSetGetPredefined(kCFCharacterSetLetter), c))
        {
            c = [string characterAtIndex: [string length] - 2];
            if ('/' == c)
                return SelfCloseTagType;
            else
                return OpenTagType;
        }
    }
    else
        return InvalidTagType;
}

NSRange extendedMatchRangeWithOpenTagInString(NSRange matchRange, NSString *string)
{
    NSRange extRange, foundRange;
    NSString *tagName, *closeTagStr;
    int level;
    
    tagName = [string substringWithRange: NSMakeRange(matchRange.location + 2,
                                                      matchRange.length - 3)];
//NSLog(@"Extend with open tag for: %@", tagName);
    extRange =  NSMakeRange(0, matchRange.location);
    closeTagStr = [NSString stringWithFormat: @"</%@>", tagName];

//NSLog(@"Looking for %@ at: [%d, %d]", tagName, extRange.location, extRange.length);
    foundRange = [string rangeOfString: tagName
                               options: NSCaseInsensitiveSearch | NSBackwardsSearch
                                 range: extRange];
    level = 1;
    while (NSNotFound != foundRange.location)
    {
        // Continue searching but now it's a bit complicated because we
        // basically have to do a real parse now to detect nested tags...
        int idx;
        unichar c;
            
        extRange = NSMakeRange(0, foundRange.location - 1);
        idx = foundRange.location;
        c = [string characterAtIndex: --idx];
        if ('/' == c
            && [string characterAtIndex: --idx] == OPEN_TAG_ELEMENT_CHAR)
        {
            level++;
//NSLog(@"  Found nested close at: [%d, %d], checking existing one in [%d, %d]",
//      foundRange.location, foundRange.length, extRange.location, extRange.length);
        }
        else if (OPEN_TAG_ELEMENT_CHAR == c)
        {
//NSLog(@"  Found nested(?) open at: [%d, %d], checking existing one in [%d, %d]",
//      foundRange.location, foundRange.length, extRange.location, extRange.length);
            level--;

            if (0 == level)
            {
                // Done!
                matchRange = NSUnionRange(matchRange, foundRange);
                // Add the '<'!
                matchRange.location--;
                matchRange.length++;
                break;
            }
        }
        foundRange = [string rangeOfString: tagName
                                   options: NSCaseInsensitiveSearch | NSBackwardsSearch
                                     range: extRange];
    }
    if (NSNotFound == foundRange.location)
    {
        NSBeep(); // Malformed xml!
        NSLog(@"[XMLTagInputManager] Malformed xml!");
        matchRange.length += matchRange.location;
        matchRange.location = 0;
    }
    return matchRange;
}

NSRange extendedMatchRangeWithCloseTagInString(NSRange matchRange, NSString *string)
{
    NSRange tagNameRange, extRange, foundRange;
    NSString *tagStr, *tagName, *closeTagStr;

    // The tagname is the range of chars from '<' until the first whitespace or '>'.
    tagStr = [string substringWithRange: NSMakeRange(matchRange.location + 1,
                                                     matchRange.length - 1)];
//NSLog(@"Extend with close tag for: %@", tagStr);
    tagNameRange = [tagStr rangeOfString: @" "];
    if (NSNotFound == tagNameRange.location)
    {
        tagNameRange = [tagStr rangeOfString: @">"];
    }
    tagName = [tagStr substringToIndex: tagNameRange.location];
    
    closeTagStr = [NSString stringWithFormat: @"</%@>", tagName];
    extRange = NSMakeRange(NSMaxRange(matchRange),
                           [string length] - NSMaxRange(matchRange));
//NSLog(@"Looking for %@ at: [%d, %d]", tagName, extRange.location, extRange.length);
    foundRange = [string rangeOfString: closeTagStr
                               options: NSCaseInsensitiveSearch
                                 range: extRange];
    if (NSNotFound != foundRange.location)
    {
        bool done;
        int level;

        extRange = NSMakeRange(NSMaxRange(matchRange),
                               [string length] - NSMaxRange(matchRange));
        matchRange = NSUnionRange(matchRange, foundRange);
//NSLog(@"  Found match at: [%d, %d], checking existing one in [%d, %d]",
//              foundRange.location, foundRange.length, extRange.location, extRange.length);
        done = false;
        level = 1;
        while (! done)
        {
            // Check if we found a nested one...
            foundRange = [string rangeOfString: tagName
                                       options: NSCaseInsensitiveSearch
                                         range: extRange];
            
            if (NSNotFound != foundRange.location)
            {
                // Continue searching but now it's a bit complicated because we
                // basically have to do a real parse now to detect nested tags...
                int idx;
                unichar c;
                
                extRange = NSMakeRange(NSMaxRange(foundRange),
                                       [string length] - NSMaxRange(foundRange));
                idx = foundRange.location;
                c = [string characterAtIndex: --idx];
                if (OPEN_TAG_ELEMENT_CHAR == c)
                {
                    level++;
//NSLog(@"  Found nested open at: [%d, %d], checking existing one in [%d, %d]",
//      foundRange.location, foundRange.length, extRange.location, extRange.length);
                    continue;
                }
                else if ('/' == c
                         && [string characterAtIndex: --idx] == OPEN_TAG_ELEMENT_CHAR)
                {
//NSLog(@"  Found nested closure at: [%d, %d], checking existing one in [%d, %d]",
//      foundRange.location, foundRange.length, extRange.location, extRange.length);
                    level--;

                    if (0 == level)
                    {
                        // Done!
                        done = true;
                        matchRange = NSUnionRange(matchRange, foundRange);
                        // Add the '>'!
                        foundRange = [string rangeOfString: @">"
                                                   options: NSLiteralSearch
                                                     range: NSMakeRange(NSMaxRange(foundRange),
                                                                        [string length] - NSMaxRange(foundRange))];
                        if (NSNotFound != foundRange.location)
                            matchRange = NSUnionRange(matchRange, foundRange);
                        else
                            break;
                    }
                }
            }
            else
            {
                break;
            }
        }
    }
    if (NSNotFound == foundRange.location)
    {
        NSBeep(); // Malformed xml!
        NSLog(@"[XMLTagInputManager] Malformed xml!");
        matchRange.length = [string length] - matchRange.location;
    }
    return matchRange;
}

@end
