import os
from google.auth.transport.requests import Request
from google.oauth2.credentials import Credentials
from google_auth_oauthlib.flow import InstalledAppFlow
from googleapiclient.discovery import build
from googleapiclient.errors import HttpError

SCOPES = ['https://www.googleapis.com/auth/spreadsheets']

class GoogleSheetsManager:
    def __init__(self):
        self.creds = None
        self.service = None
        self.authenticate()

    def authenticate(self):
        if os.path.exists('token.json'):
            self.creds = Credentials.from_authorized_user_file('token.json', SCOPES)
        if not self.creds or not self.creds.valid:
            if self.creds and self.creds.expired and self.creds.refresh_token:
                self.creds.refresh(Request())
            else:
                client_secret_file = 'client_secret_532399732348-bim7k3ldpj2ot1lnu0r76b3jc9i4k7s4.apps.googleusercontent.com.json'
                flow = InstalledAppFlow.from_client_secrets_file(
                    client_secret_file, SCOPES)
                self.creds = flow.run_local_server(port=0)
            with open('token.json', 'w') as token:
                token.write(self.creds.to_json())
        self.service = build('sheets', 'v4', credentials=self.creds)

    def create_sheet(self, title):
        try:
            spreadsheet = {
                'properties': {
                    'title': title
                }
            }
            spreadsheet = self.service.spreadsheets().create(body=spreadsheet,
                                                             fields='spreadsheetId').execute()
            return spreadsheet.get('spreadsheetId')
        except HttpError as error:
            print(f"an error occurred: {error}")
            return None

    def export_data(self, spreadsheet_id, range_name, values):
        try:
            body = {
                'values': values
            }
            result = self.service.spreadsheets().values().update(
                spreadsheetId=spreadsheet_id, range=range_name,
                valueInputOption='RAW', body=body).execute()
            return True
        except HttpError as error:
            print(f"an error occurred: {error}")
            return False

def main():
    manager = GoogleSheetsManager()
    spreadsheet_id = manager.create_sheet("my new sheet")
    if spreadsheet_id:
        data = [
            ["name", "age", "city"],
            ["alice", 30, "new york"],
            ["bob", 25, "san francisco"]
        ]
        success = manager.export_data(spreadsheet_id, "sheet1!a1:c3", data)
        if success:
            print("data exported successfully")
        else:
            print("failed to export data")

if __name__ == '__main__':
    main()