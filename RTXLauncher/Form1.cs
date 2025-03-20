using System.ComponentModel;
using System.Xml.Serialization;

namespace RTXLauncher
{
    public partial class Form1 : Form
    {

        public Form1()
        {
            InitializeComponent();
        }

        protected override void OnClosing(CancelEventArgs e)
        {
            base.OnClosing(e);
            SaveSettings();
        }

        public void LoadSettings()
        {
            var serializer = new XmlSerializer(typeof(SettingsData));
            var filePath = "settings.xml";
            if (File.Exists(filePath))
            {
                using (var reader = new StreamReader(filePath))
                {
                    settingsDataBindingSource.DataSource = (SettingsData)serializer.Deserialize(reader);
                }
            }
            else
            {
                settingsDataBindingSource.DataSource = new SettingsData();
            }
        }
        public void SaveSettings()
        {
            // save to xml config file
            var serializer = new XmlSerializer(typeof(SettingsData));
            var filePath = "settings.xml";
            var dataSource = settingsDataBindingSource.DataSource as SettingsData;
            if (dataSource != null)
            {
                using (var writer = new StreamWriter(filePath))
                {
                    serializer.Serialize(writer, dataSource);
                }
            }
            else
            {
                // Handle the case where the data source is not of type SettingsData
                throw new InvalidOperationException("Data source is not of type SettingsData.");
            }
        }

        private void Form1_Load(object sender, EventArgs e)
        {
            // refresh the form
            LoadSettings();
            settingsDataBindingSource.ResetBindings(false);
        }

        private void groupBox1_Enter(object sender, EventArgs e)
        {

        }

        private void LaunchGameButton_Click(object sender, EventArgs e)
        {
            LauncherProgram.LaunchGameWithSettings(settingsDataBindingSource.DataSource as SettingsData);
        }

        private void textBox2_TextChanged(object sender, EventArgs e)
        {

        }

        private void label1_Click(object sender, EventArgs e)
        {

        }

        private void label2_Click(object sender, EventArgs e)
        {

        }

        private void groupBox2_Enter(object sender, EventArgs e)
        {

        }
    }
}
