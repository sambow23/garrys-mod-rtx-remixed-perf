namespace RTXLauncher
{
    partial class Form1
    {
        /// <summary>
        ///  Required designer variable.
        /// </summary>
        private System.ComponentModel.IContainer components = null;

        /// <summary>
        ///  Clean up any resources being used.
        /// </summary>
        /// <param name="disposing">true if managed resources should be disposed; otherwise, false.</param>
        protected override void Dispose(bool disposing)
        {
            if (disposing && (components != null))
            {
                components.Dispose();
            }
            base.Dispose(disposing);
        }

        #region Windows Form Designer generated code

        /// <summary>
        ///  Required method for Designer support - do not modify
        ///  the contents of this method with the code editor.
        /// </summary>
        private void InitializeComponent()
        {
            components = new System.ComponentModel.Container();
            groupBox1 = new GroupBox();
            CustomWidthBox = new NumericUpDown();
            settingsDataBindingSource = new BindingSource(components);
            CustomHeightBox = new NumericUpDown();
            label2 = new Label();
            label1 = new Label();
            checkBox1 = new CheckBox();
            comboBox1 = new ComboBox();
            LaunchGameButton = new Button();
            groupBox2 = new GroupBox();
            checkBox2 = new CheckBox();
            groupBox1.SuspendLayout();
            ((System.ComponentModel.ISupportInitialize)CustomWidthBox).BeginInit();
            ((System.ComponentModel.ISupportInitialize)settingsDataBindingSource).BeginInit();
            ((System.ComponentModel.ISupportInitialize)CustomHeightBox).BeginInit();
            groupBox2.SuspendLayout();
            SuspendLayout();
            // 
            // groupBox1
            // 
            groupBox1.Controls.Add(CustomWidthBox);
            groupBox1.Controls.Add(CustomHeightBox);
            groupBox1.Controls.Add(label2);
            groupBox1.Controls.Add(label1);
            groupBox1.Controls.Add(checkBox1);
            groupBox1.Controls.Add(comboBox1);
            groupBox1.Location = new Point(12, 12);
            groupBox1.Name = "groupBox1";
            groupBox1.Size = new Size(260, 123);
            groupBox1.TabIndex = 0;
            groupBox1.TabStop = false;
            groupBox1.Text = "Resolution";
            groupBox1.Enter += groupBox1_Enter;
            // 
            // CustomWidthBox
            // 
            CustomWidthBox.DataBindings.Add(new Binding("Value", settingsDataBindingSource, "Width", true));
            CustomWidthBox.Location = new Point(6, 91);
            CustomWidthBox.Maximum = new decimal(new int[] { 100000, 0, 0, 0 });
            CustomWidthBox.Name = "CustomWidthBox";
            CustomWidthBox.Size = new Size(47, 23);
            CustomWidthBox.TabIndex = 6;
            CustomWidthBox.Value = new decimal(new int[] { 1920, 0, 0, 0 });
            // 
            // settingsDataBindingSource
            // 
            settingsDataBindingSource.DataSource = typeof(SettingsData);
            // 
            // CustomHeightBox
            // 
            CustomHeightBox.DataBindings.Add(new Binding("Value", settingsDataBindingSource, "Height", true));
            CustomHeightBox.Location = new Point(77, 91);
            CustomHeightBox.Maximum = new decimal(new int[] { 100000, 0, 0, 0 });
            CustomHeightBox.Name = "CustomHeightBox";
            CustomHeightBox.Size = new Size(47, 23);
            CustomHeightBox.TabIndex = 2;
            CustomHeightBox.Value = new decimal(new int[] { 1080, 0, 0, 0 });
            // 
            // label2
            // 
            label2.AutoSize = true;
            label2.Location = new Point(6, 73);
            label2.Name = "label2";
            label2.Size = new Size(108, 15);
            label2.TabIndex = 5;
            label2.Text = "Custom Resolution";
            label2.Click += label2_Click;
            // 
            // label1
            // 
            label1.AutoSize = true;
            label1.Location = new Point(57, 96);
            label1.Name = "label1";
            label1.Size = new Size(14, 15);
            label1.TabIndex = 4;
            label1.Text = "X";
            label1.Click += label1_Click;
            // 
            // checkBox1
            // 
            checkBox1.AutoSize = true;
            checkBox1.DataBindings.Add(new Binding("Checked", settingsDataBindingSource, "UseCustomResolution", true));
            checkBox1.Location = new Point(6, 51);
            checkBox1.Name = "checkBox1";
            checkBox1.Size = new Size(149, 19);
            checkBox1.TabIndex = 1;
            checkBox1.Text = "Use Custom Resolution";
            checkBox1.UseVisualStyleBackColor = true;
            // 
            // comboBox1
            // 
            comboBox1.DisplayMember = "1920x1080";
            comboBox1.FormattingEnabled = true;
            comboBox1.Items.AddRange(new object[] { "1920x1080", "2560x1440" });
            comboBox1.Location = new Point(6, 22);
            comboBox1.Name = "comboBox1";
            comboBox1.Size = new Size(248, 23);
            comboBox1.TabIndex = 0;
            comboBox1.Text = "1920x1080";
            // 
            // LaunchGameButton
            // 
            LaunchGameButton.Location = new Point(12, 295);
            LaunchGameButton.Name = "LaunchGameButton";
            LaunchGameButton.Size = new Size(260, 23);
            LaunchGameButton.TabIndex = 1;
            LaunchGameButton.Text = "Launch Game";
            LaunchGameButton.UseVisualStyleBackColor = true;
            LaunchGameButton.Click += LaunchGameButton_Click;
            // 
            // groupBox2
            // 
            groupBox2.Controls.Add(checkBox2);
            groupBox2.Location = new Point(12, 141);
            groupBox2.Name = "groupBox2";
            groupBox2.Size = new Size(260, 123);
            groupBox2.TabIndex = 7;
            groupBox2.TabStop = false;
            groupBox2.Text = "Garry's Mod";
            groupBox2.Enter += groupBox2_Enter;
            // 
            // checkBox2
            // 
            checkBox2.AutoSize = true;
            checkBox2.Checked = true;
            checkBox2.CheckState = CheckState.Checked;
            checkBox2.DataBindings.Add(new Binding("Checked", settingsDataBindingSource, "LoadWorkshopAddons", true));
            checkBox2.Location = new Point(6, 22);
            checkBox2.Name = "checkBox2";
            checkBox2.Size = new Size(153, 19);
            checkBox2.TabIndex = 1;
            checkBox2.Text = "Load Workshop Addons";
            checkBox2.UseVisualStyleBackColor = true;
            // 
            // Form1
            // 
            AutoScaleDimensions = new SizeF(7F, 15F);
            AutoScaleMode = AutoScaleMode.Font;
            ClientSize = new Size(284, 330);
            Controls.Add(groupBox2);
            Controls.Add(LaunchGameButton);
            Controls.Add(groupBox1);
            Name = "Form1";
            Text = " Garry's Mod RTX Launcher";
            Load += Form1_Load;
            groupBox1.ResumeLayout(false);
            groupBox1.PerformLayout();
            ((System.ComponentModel.ISupportInitialize)CustomWidthBox).EndInit();
            ((System.ComponentModel.ISupportInitialize)settingsDataBindingSource).EndInit();
            ((System.ComponentModel.ISupportInitialize)CustomHeightBox).EndInit();
            groupBox2.ResumeLayout(false);
            groupBox2.PerformLayout();
            ResumeLayout(false);
        }

        #endregion

        private GroupBox groupBox1;
        private Button LaunchGameButton;
        private ComboBox comboBox1;
        private CheckBox checkBox1;
        private Label label1;
        private Label label2;
        private NumericUpDown CustomWidthBox;
        private NumericUpDown CustomHeightBox;
        private GroupBox groupBox2;
        private CheckBox checkBox2;
        public BindingSource settingsDataBindingSource;
    }
}
