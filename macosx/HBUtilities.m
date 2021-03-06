/*  HBUtilities.m $

 This file is part of the HandBrake source code.
 Homepage: <http://handbrake.fr/>.
 It may be used under the terms of the GNU General Public License. */

#import "HBUtilities.h"
#include "common.h"

@implementation HBUtilities

+ (NSString *)appSupportPath
{
    NSString *appSupportPath = [[NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory,
                                                                     NSUserDomainMask,
                                                                     YES) firstObject] stringByAppendingPathComponent:@"HandBrake"];

    NSFileManager *fileManager = [NSFileManager defaultManager];
    if (![fileManager fileExistsAtPath:appSupportPath])
        [fileManager createDirectoryAtPath:appSupportPath withIntermediateDirectories:YES attributes:nil error:NULL];

    return appSupportPath;
}

+ (void)writeToActivityLog:(const char *)format, ...
{
    va_list args;
    va_start(args, format);
    if (format != nil)
    {
        char str[1024];
        vsnprintf(str, 1024, format, args);

        time_t _now = time(NULL);
        struct tm *now  = localtime(&_now);
        fprintf(stderr, "[%02d:%02d:%02d] macgui: %s\n", now->tm_hour, now->tm_min, now->tm_sec, str);
    }
    va_end(args);
}

+ (NSString *)automaticNameForSource:(NSString *)sourceName
                               title:(NSUInteger)title
                            chapters:(NSRange)chaptersRange
                             quality:(NSString *)quality
                             bitrate:(NSString *)bitrate
                          videoCodec:(uint32_t *)codec
{
    NSMutableString *name = [[[NSMutableString alloc] init] autorelease];
    // The format array contains the tokens as NSString
    NSArray *format = [[NSUserDefaults standardUserDefaults] objectForKey:@"HBAutoNamingFormat"];

    for (NSString *formatKey in format)
    {
        if ([formatKey isEqualToString:@"{Source}"])
        {
            if ([[[NSUserDefaults standardUserDefaults] objectForKey:@"HBAutoNamingRemoveUnderscore"] boolValue])
            {
                sourceName = [sourceName stringByReplacingOccurrencesOfString:@"_" withString:@" "];
            }
            if ([[[NSUserDefaults standardUserDefaults] objectForKey:@"HBAutoNamingRemovePunctuation"] boolValue])
            {
                sourceName = [sourceName stringByReplacingOccurrencesOfString:@"-" withString:@""];
                sourceName = [sourceName stringByReplacingOccurrencesOfString:@"." withString:@""];
                sourceName = [sourceName stringByReplacingOccurrencesOfString:@"," withString:@""];
                sourceName = [sourceName stringByReplacingOccurrencesOfString:@";" withString:@""];
            }
            if ([[[NSUserDefaults standardUserDefaults] objectForKey:@"HBAutoNamingTitleCase"] boolValue])
            {
                sourceName = [sourceName capitalizedString];
            }
            [name appendString:sourceName];
        }
        else if ([formatKey isEqualToString:@"{Title}"])
        {
            [name appendFormat:@"%lu", (unsigned long)title];
        }
        else if ([formatKey isEqualToString:@"{Date}"])
        {
            NSDate *date = [NSDate date];
            NSString *dateString = nil;
            NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
            [formatter setDateStyle:NSDateFormatterShortStyle];
            [formatter setTimeStyle:NSDateFormatterNoStyle];
            dateString = [[formatter stringFromDate:date] stringByReplacingOccurrencesOfString:@"/" withString:@"-"];
            [name appendString:dateString];
        }
        else if ([formatKey isEqualToString:@"{Time}"])
        {
            NSDate *date = [NSDate date];
            NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
            [formatter setDateStyle:NSDateFormatterNoStyle];
            [formatter setTimeStyle:NSDateFormatterShortStyle];
            [name appendString:[formatter stringFromDate:date]];
        }
        else if ([formatKey isEqualToString:@"{Chapters}"])
        {
            if (chaptersRange.location == chaptersRange.length)
            {
                [name appendFormat:@"%lu", (unsigned long)chaptersRange.location];
            }
            else
            {
                [name appendFormat:@"%lu-%lu", (unsigned long)chaptersRange.location, (unsigned long)chaptersRange.length];
            }
        }
        else if ([formatKey isEqualToString:@"{Quality/Bitrate}"])
        {
            if (quality)
            {
                // Append the right quality suffix for the selected codec (rf/qp)
                [name appendString:[[NSString stringWithUTF8String:hb_video_quality_get_name(codec)] lowercaseString]];
                [name appendString:quality];
            }
            else
            {
                [name appendString:@"abr"];
                [name appendString:bitrate];
            }
        }
        else
        {
            [name appendString:formatKey];
        }
    }

    return [[name copy] autorelease];
}


@end
