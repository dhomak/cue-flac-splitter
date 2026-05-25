#!/usr/bin/env python3
"""
RuTracker Magnet Link Scraper
Extracts magnet links from RuTracker torrent pages
Requires: requests, beautifulsoup4, striprtf
Install: pip install requests beautifulsoup4 striprtf
"""

import requests
from bs4 import BeautifulSoup
import re
import time
import sys
import os
from pathlib import Path
try:
    from striprtf.striprtf import rtf_to_text
except ImportError:
    rtf_to_text = None

class RuTrackerScraper:
    def __init__(self, username=None, password=None):
        self.session = requests.Session()
        self.session.headers.update({
            'User-Agent': 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36'
        })
        self.base_url = 'https://rutracker.net/forum'
        
        if username and password:
            self.login(username, password)
    
    def login(self, username, password):
        """Login to RuTracker"""
        login_url = f'{self.base_url}/login.php'
        login_data = {
            'login_username': username,
            'login_password': password,
            'login': 'Вход'
        }
        
        print(f"Logging in as {username}...")
        response = self.session.post(login_url, data=login_data)
        
        if 'logged-in-username' in response.text or response.cookies.get('bb_session'):
            print("✓ Login successful")
            return True
        else:
            print("✗ Login failed - check credentials")
            return False
    
    def get_magnet_link(self, url):
        """Extract magnet link from a RuTracker page"""
        try:
            print(f"Fetching: {url}")
            response = self.session.get(url, timeout=10)
            response.raise_for_status()
            
            soup = BeautifulSoup(response.text, 'html.parser')
            
            # Look for magnet link in the page
            magnet_link = None
            
            # Method 1: Find magnet: links directly
            for link in soup.find_all('a', href=re.compile(r'^magnet:\?')):
                magnet_link = link['href']
                break
            
            # Method 2: Look in download buttons or specific classes
            if not magnet_link:
                # RuTracker often has magnet links in specific elements
                for element in soup.find_all(['a', 'button'], class_=re.compile(r'magnet|download')):
                    if element.get('href') and element['href'].startswith('magnet:'):
                        magnet_link = element['href']
                        break
            
            # Method 3: Search for magnet links in the raw HTML
            if not magnet_link:
                magnet_match = re.search(r'magnet:\?[^\s"\'<>]+', response.text)
                if magnet_match:
                    magnet_link = magnet_match.group(0)
            
            if magnet_link:
                print(f"✓ Found magnet link")
                return magnet_link
            else:
                print(f"✗ No magnet link found (may require login)")
                return None
                
        except requests.exceptions.RequestException as e:
            print(f"✗ Error fetching {url}: {e}")
            return None
        except Exception as e:
            print(f"✗ Unexpected error: {e}")
            return None
    
    def scrape_urls(self, urls, delay=1.5):
        """Scrape multiple URLs with delay between requests"""
        results = {}
        
        for i, url in enumerate(urls, 1):
            print(f"\n[{i}/{len(urls)}]")
            magnet = self.get_magnet_link(url)
            results[url] = magnet
            
            # Delay between requests to be polite
            if i < len(urls):
                time.sleep(delay)
        
        return results


def read_urls_from_file(filepath):
    """Read URLs from TXT or RTF file"""
    path = Path(filepath)
    extension = path.suffix.lower()
    
    urls = []
    
    try:
        if extension == '.rtf':
            # Read RTF file
            if rtf_to_text is None:
                print("Error: striprtf library not installed")
                print("Install it with: pip install striprtf")
                return []
            
            with open(filepath, 'r', encoding='utf-8') as f:
                rtf_content = f.read()
            
            text = rtf_to_text(rtf_content)
        
        elif extension == '.txt':
            # Read plain text file
            with open(filepath, 'r', encoding='utf-8') as f:
                text = f.read()
        
        else:
            print(f"Error: Unsupported file type '{extension}'")
            print("Supported types: .txt, .rtf")
            return []
        
        # Extract URLs from text
        # Look for rutracker.net URLs
        url_pattern = r'https?://rutracker\.net/forum/viewtopic\.php\?t=\d+'
        urls = re.findall(url_pattern, text)
        
        # Remove duplicates while preserving order
        seen = set()
        unique_urls = []
        for url in urls:
            if url not in seen:
                seen.add(url)
                unique_urls.append(url)
        
        return unique_urls
    
    except Exception as e:
        print(f"Error reading file: {e}")
        return []


def main():
    print("RuTracker Magnet Link Scraper")
    print("=" * 50)
    
    # Check for input file argument
    if len(sys.argv) < 2:
        print("Error: No input file specified")
        print("Usage: python rutracker_scraper.py <file.txt|file.rtf>")
        sys.exit(1)
    
    input_file = sys.argv[1]
    if not os.path.exists(input_file):
        print(f"Error: File '{input_file}' not found")
        sys.exit(1)
    
    print(f"Reading URLs from: {input_file}")
    urls = read_urls_from_file(input_file)
    
    if not urls:
        print("Error: No URLs found in file")
        sys.exit(1)
    
    print(f"Found {len(urls)} URLs")
    
    # Option 1: Try without login (may not work)
    print("\nAttempting without login...")
    scraper = RuTrackerScraper()
    results = scraper.scrape_urls(urls)
    
    # If no results, prompt for login
    if not any(results.values()):
        print("\n" + "=" * 50)
        print("No magnet links found. Login required.")
        username = input("RuTracker username: ").strip()
        password = input("RuTracker password: ").strip()
        
        if username and password:
            scraper = RuTrackerScraper(username, password)
            results = scraper.scrape_urls(urls)
    
    # Print results
    print("\n" + "=" * 50)
    print("RESULTS")
    print("=" * 50)

    for url, magnet in results.items():
        topic_id = url.split('t=')[1] if 't=' in url else url
        print(f"\nTopic {topic_id}:")
        print(f"URL: {url}")
        if magnet:
            print(f"Magnet: {magnet}")
        else:
            print("Magnet: NOT FOUND")

    # Print magnet-only summary for the UI to collect
    magnets = [m for m in results.values() if m]
    if magnets:
        print("\n%%MAGNETS_START%%")
        for m in magnets:
            print(m)
        print("%%MAGNETS_END%%")
    


if __name__ == "__main__":
    main()