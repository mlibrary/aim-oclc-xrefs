# Opens file example.txt, in directory /in, and gets one mmsid and one OCLC number per line
# Suggestion: ruby oclc_cross_ref_process.rb example.txt output.txt
require "faraday"
require "stringio"
require "marc"

# require_relative "./lib/update_alma"

require_relative "./lib/alma_bib"
require_relative "./lib/worldcat_bib"

output_file = ARGV[1]
input_file = ARGV[0]

module OCLCProcessor
  def self.process(input_file, output_file)
    linecount = 0
    countandskipcount = 0
    exceptions = []
    File.open("out/#{output_file}", "w") do |out|
      File.open("in/#{input_file}", "r").each_line do |line|
        line.chomp!
        linecount += 1

        mmsid, oclcnum = line.split("\t")
        mmsid.strip!
        oclcnum.strip!

        begin
          alma_bib = AlmaBib.for(mmsid)
        rescue
          # this means the mms id in the xref file wasn't found. It's an error.
          # Report it.
          out.print "#{linecount}\t#{mmsid}\t#{oclcnum}\tMMSID Doesn't Exist\n"
          exceptions.push("#{mmsid}\t#{oclcnum}\tMMSID Not found")
          next
        end

        # Any OCLC num in Alma 035?
        if alma_bib.no_oclc?
          # Process $a into XML
          # puts "process $a into xml"
          updatealmaresult = alma_bib.update_035(new_oclc_number: oclcnum)
          # puts updatealmaresult
          out.print "#{linecount}\t#{mmsid}\t#{oclcnum}\t#{updatealmaresult} with 035 $a only\n"
          # And go to next line
          next
        end

        oclcnumbersfromalma = alma_bib.oclc_all
        # Same as file OCLC num?
        # 'oclcnum' is the cross reference file OCLC number, 'oclcnumbersfromalma' is an array of the numbers from Alma
        # Is the OCLC number in the array of OCLC numbers? Returns true if match, false if no match.
        if alma_bib.has_oclc?(oclcnum)
          # count and skip
          out.print "#{linecount}\t#{mmsid}\t#{oclcnum}\tCount and skip\n"
          countandskipcount += 1
          # And go to next line
          next
        else
          # puts "keep going"
        end

        # Number change? (019 in Worldcat)
        # I think: take the OCLC number from the cross reference file, 'oclcnum', submit it to the Worldcat API and see if there are any 019 fields with the OCLC number from Alma?
        # 'oclcnumbersfromalma' is an array of oclc numbers from Alma (but I think there will only be one actual number), 'oclcnum' is the file OCLC number
        worldcat_bib = WorldcatBib.for(oclcnum)

        if worldcat_bib.match_any_019?(oclcnumbersfromalma)
          # Process $a and $z into xml
          # 'oclcnum' will be the $a, the $z(s) will be from the 'inohonenine' method: 'numberchangeresult'.
          updatealmaresult = alma_bib.update_035(new_oclc_number: oclcnum, numbers_from_019: worldcat_bib.tag_019)

          # puts updatealmaresult

          # Add a line to the report with the updatealamresult.
          # puts "#{linecount}\t#{mmsid}\t#{oclcnum}\n"
          out.print "#{linecount}\t#{mmsid}\t#{oclcnum}\t#{updatealmaresult} with 035 $a and $z(s)\n"
        else
          # Report error
          # puts "Report error: Number Change No"
          out.print "#{linecount}\t#{mmsid}\t#{oclcnum}\tNumber Change No; Report error\n"
          exceptions.push("#{mmsid}\t#{oclcnum}\tNo number change found; Error")
          # And go to next line
          # puts "keep going"
          # puts numberchangeresult
        end
      end
    end
    File.write("out/#{output_file}.errors", exceptions.join("\n")) 
    
  end
end

OCLCProcessor.process(input_file, output_file) if input_file && output_file
